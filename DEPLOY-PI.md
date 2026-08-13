# Exposer RailMapAPI (Raspberry Pi) sur un domaine OVH

Runbook pour la beta TestFlight : le Pi n'ouvre **aucun port entrant**, le domaine
reste acheté chez OVH, le TLS et le filtrage sont assurés par Cloudflare Tunnel.

Cible : `api.jeremiepatot.fr`.

```
iPhone (TestFlight)
   │  https://api.jeremiepatot.fr
   ▼
Cloudflare edge  ── TLS, WAF, rate limit, DDoS
   │  tunnel sortant (QUIC/443)
   ▼
cloudflared (systemd, sur le Pi)
   │  http://127.0.0.1:8090
   ▼
Docker : rail-map-a-p-i  (network_mode: host, écoute sur 127.0.0.1:8090)
```

---

## 0. Le Pi n'est pas vierge

`raspberrypi.home` = **192.168.1.50**. Relevé du 11 août 2026 :

| Port | Service occupant |
|------|------------------|
| 22   | SSH |
| 80 / 443 | **Pi-hole** (DNS + interface admin) |
| 8080 | **Zigbee2MQTT** (WindFront) |

Conséquences :

- **L'API ne peut pas utiliser 8080.** On prend **8090** côté hôte, 8080 reste le
  port interne du conteneur.
- **80 et 443 sont pris par Pi-hole** → un reverse proxy type Caddy aurait été
  pénible à caser. Cloudflare Tunnel n'a besoin d'aucun port entrant : c'est un
  argument de plus pour cette solution.
- **Ce Pi rend le DNS de toute la maison.** Si l'ingestion GTFS sature le CPU ou
  la RAM, tu perds le DNS domestique et la domotique Zigbee en même temps.
  Prévoir de plafonner le conteneur (voir §1) et surveiller.
- **Le réseau bridge Docker est défaillant pour les réseaux nouvellement créés.**
  Constaté le 11 août 2026 : le conteneur obtient bien son IP, la paire veth est
  `UP,LOWER_UP` des deux côtés et rattachée au bridge, les règles nftables sont
  complètes et identiques à celles d'un bridge fonctionnel — mais `eth0` du
  conteneur reste à **0 octet reçu** et l'hôte ne résout jamais l'ARP de l'IP du
  conteneur. Les bridges préexistants (`arr_default`, `pihole_default`)
  fonctionnent, un bridge neuf non ; recréer le réseau ne corrige rien, et le STP
  est désactivé. D'où le `network_mode: host` du `docker-compose.yml`.
  **C'est un problème latent de la machine**, indépendant de RailMapAPI : tout
  nouveau projet Docker sur ce Pi rencontrera la même chose. À investiguer à part
  (piste : version du noyau vs Docker 29 en nf_tables).

---

## 1. Déployer et durcir le conteneur sur le Pi

Toutes les commandes de ce runbook s'exécutent **sur le Pi**, via SSH :

```bash
ssh <user>@192.168.1.50
```

### Matériel confirmé (11 août 2026)

```
Raspberry Pi 5 Model B Rev 1.1
RAM        7,9 Gi (5,7 Gi disponibles)
swap       zram0 2 Gi, 1,4 Gi utilisés   → compressé en RAM, pas d'écriture disque
/          /dev/mmcblk0p2  29 G, 11 G libres      carte SD
/mnt/ssd   /dev/nvme0n1p1  3,6 T, 39 G libres     NVMe Crucial P3 Plus 4 To
/var/log   log2ram 128 M                          déjà en place
Docker     29.0.4 / Compose v2.40.3, data-root = /mnt/ssd/docker-data
```

Le Pi est bien mieux équipé que ce que laissait croire le premier relevé :

- **Le data-root Docker est déjà sur le NVMe.** Images, couches et cache de build
  ne touchent pas la carte SD — rien à déplacer.
- **Le swap est du zram**, donc de la RAM compressée. Les 1,4 Gi utilisés ne
  sont pas des écritures sur carte SD et ne posent pas de problème d'usure.
- **`log2ram` couvre déjà `/var/log`**, l'autre grand consommateur d'écritures.

Le seul point à surveiller : **le NVMe est rempli à 99 %**, il ne reste que 39 Go.
Suffisant pour le build (pic ~9 Go), mais à vérifier avant chaque reconstruction :

```bash
df -h /mnt/ssd
docker system df
```

> ⚠️ **Ne pas lancer `docker system prune -af` sur ce Pi.** Il héberge 9 conteneurs,
> dont Pi-hole (le DNS de toute la maison) et Zigbee2MQTT. `prune -a` supprime les
> conteneurs arrêtés et toute image non rattachée à un conteneur : un service
> temporairement à l'arrêt au mauvais moment perd son image, et il faut la
> retélécharger pour le relancer. Le cache de build est déjà à 0 de toute façon,
> il n'y a rien à y gagner. Pour faire de la place, viser plutôt les données de
> `/mnt/ssd` hors Docker.

### Récupérer le code

Le `docker-compose.yml` corrigé (bind `127.0.0.1:8090`, `restart: unless-stopped`,
limite mémoire) **n'est pas encore sur `main`** — il est en local sur la branche
`fix/shape-rendering` du Mac. Le pousser d'abord, sinon le clone récupère
l'ancienne version qui expose `0.0.0.0:8080` et se heurte à Zigbee2MQTT.

```bash
git clone https://github.com/RailMapiOS/RailMapAPI.git ~/RailMapAPI
cd ~/RailMapAPI
echo "API_AUTH_TOKENS=$(openssl rand -base64 32)" > .env
echo "LOG_LEVEL=notice" >> .env
```

### Construire et lancer

```bash
time docker compose build     # compter un bon moment sur Pi 5
docker compose up -d app
docker builder prune -af      # récupérer l'espace du cache de build
df -h /
```

Si le build échoue en OOM malgré les 8 Go, limiter le parallélisme en ajoutant
`-j 2` à la ligne `swift build` du `Dockerfile`.

Garder ce token de côté : il devra être copié dans `APIKeys.swift` côté iOS.

Plafonner les ressources pour protéger Pi-hole et Zigbee2MQTT — ajouter dans
`docker-compose.yml`, sous le service `app` :

```yaml
    deploy:
      resources:
        limits:
          memory: 1g
```

Vérifier que le port est bien sur la loopback et pas exposé au LAN :

```bash
ss -ltnp | grep 8090   # doit afficher 127.0.0.1:8090, pas 0.0.0.0:8090
curl -s http://127.0.0.1:8090/hello
```

Depuis le Mac, `curl http://192.168.1.50:8090/hello` doit désormais échouer.

Pare-feu : ne laisser entrer que ce qui est nécessaire. **Attention, Pi-hole sert
le DNS au réseau local** — bloquer le port 53 couperait Internet à toute la maison.

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 53             # Pi-hole DNS
sudo ufw allow from 192.168.1.0/24 to any port 80,443 proto tcp   # admin Pi-hole
sudo ufw allow from 192.168.1.0/24 to any port 8080 proto tcp     # Zigbee2MQTT
sudo ufw enable
```

---

## 2. Basculer le DNS du domaine vers Cloudflare

Le domaine **reste enregistré chez OVH** ; seuls les serveurs DNS changent.
Cloudflare Tunnel exige que la zone du hostname soit gérée par Cloudflare.

### État de la zone au 11 août 2026 (à reproduire à l'identique)

| Type | Nom               | Valeur                          | Enjeu |
|------|-------------------|---------------------------------|-------|
| NS   | `jeremiepatot.fr` | `ns104.ovh.net`, `dns104.ovh.net` | remplacés par Cloudflare |
| MX   | `jeremiepatot.fr` | `1 mx1.mail.ovh.net`            | **critique — mail** |
| MX   | `jeremiepatot.fr` | `5 mx2.mail.ovh.net`            | **critique — mail** |
| MX   | `jeremiepatot.fr` | `100 mx3.mail.ovh.net`          | **critique — mail** |
| TXT  | `jeremiepatot.fr` | `v=spf1 include:mx.ovh.com -all` | **critique — délivrabilité** |
| TXT  | `jeremiepatot.fr` | `1|www.jeremiepatot.fr`         | marqueur de redirection OVH |
| A    | `jeremiepatot.fr` | `213.186.33.5`                  | parking OVH « Site en construction » |
| A    | `www`             | `213.186.33.5`                  | idem |

Ni DKIM (`ovh`, `selector1/2`, `default`, `mail`), ni `_dmarc`, ni
`autodiscover`/`autoconfig` ne sont publiés — rien d'autre à sauver.
Le seul service réellement vivant est **le mail OVH**.

### Marche à suivre

1. Créer un compte Cloudflare, *Add a site* → `jeremiepatot.fr` → plan **Free**.
2. Cloudflare scanne la zone et propose les enregistrements. **Comparer avec le
   tableau ci-dessus, ligne par ligne.** Les 3 MX et le SPF doivent être
   présents, en mode **DNS only** (nuage gris) — un MX proxifié ne fonctionne pas.
3. Cloudflare affiche deux nameservers du type `xxx.ns.cloudflare.com`.
4. OVH Manager → *Web Cloud* → *Noms de domaine* → `jeremiepatot.fr` → onglet
   **Serveurs DNS** → *Modifier les serveurs DNS* → mode **personnalisé** →
   saisir les deux NS Cloudflare → valider.
5. Propagation : de quelques minutes à ~24 h.

### Contrôle après bascule

```bash
dig NS  jeremiepatot.fr +short   # doit renvoyer les NS Cloudflare
dig MX  jeremiepatot.fr +short   # doit renvoyer les 3 mx*.mail.ovh.net
dig TXT jeremiepatot.fr +short   # doit contenir le SPF
```

Puis **s'envoyer un mail de test** sur l'adresse du domaine avant d'aller plus loin.

> La redirection `jeremiepatot.fr` → `www.jeremiepatot.fr` est un service OVH
> piloté depuis leur interface. Elle peut cesser de fonctionner une fois la zone
> chez Cloudflare. Comme la cible est la page « Site en construction », c'est sans
> conséquence ; si besoin, la refaire avec une *Redirect Rule* Cloudflare.

---

## 3. Installer le tunnel sur le Pi

Le Pi est en ARM64 (Raspberry Pi OS 64-bit) :

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb -o /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb
cloudflared --version
```

(Pi OS 32-bit → `cloudflared-linux-arm`. Vérifier avec `uname -m` : `aarch64` = arm64.)

Authentifier — ouvre une URL à coller dans un navigateur, puis choisir le domaine :

```bash
cloudflared tunnel login
```

Créer le tunnel et l'enregistrement DNS :

```bash
cloudflared tunnel create railmap-api
cloudflared tunnel route dns railmap-api api.jeremiepatot.fr
```

La commande `create` affiche un UUID et écrit
`~/.cloudflared/<UUID>.json`. `route dns` crée automatiquement le CNAME proxifié
dans la zone Cloudflare.

Configuration :

```bash
sudo mkdir -p /etc/cloudflared
sudo cp ~/.cloudflared/<UUID>.json /etc/cloudflared/
sudo nano /etc/cloudflared/config.yml
```

```yaml
tunnel: railmap-api
credentials-file: /etc/cloudflared/<UUID>.json

ingress:
  - hostname: api.jeremiepatot.fr
    service: http://127.0.0.1:8090
    originRequest:
      connectTimeout: 30s
      # Le calcul de shape peut être long à froid (OSRM / Overpass).
      # Cloudflare coupe de toute façon à 100 s côté edge (erreur 524).
      httpHostHeader: api.jeremiepatot.fr
  - service: http_status:404
```

Le catch-all `http_status:404` est obligatoire, sinon `cloudflared` refuse de démarrer.

Installer en service :

```bash
sudo cloudflared service install
sudo systemctl enable --now cloudflared
systemctl status cloudflared
journalctl -u cloudflared -f
```

Test depuis le Mac :

```bash
curl -i https://api.jeremiepatot.fr/hello
TOKEN=<le token de .env>
curl -H "Authorization: Bearer $TOKEN" https://api.jeremiepatot.fr/sources | jq
```

---

## 4. Régler Cloudflare pour une beta

Dashboard → zone `jeremiepatot.fr`.

**SSL/TLS**
- Mode de chiffrement : **Full** (l'origine est le tunnel, pas besoin de Strict).
- *Edge Certificates* → **Always Use HTTPS** : on.
- *Minimum TLS Version* : **1.2**.

**Security → WAF → Custom rules** (5 règles offertes sur le plan Free)

Règle 1 — *Block unauthenticated* : tout ce qui n'a pas de header
`Authorization` est bloqué au bord, sans jamais atteindre le Pi.

```
Expression :
  (http.host eq "api.jeremiepatot.fr"
   and not starts_with(http.request.uri.path, "/hello")
   and not any(http.request.headers.names[*] == "authorization"))
Action : Block
```

`http.request.headers.names` normalise les noms en minuscules — c'est la forme
documentée pour tester l'absence d'un en-tête.

Règle 2 — *Méthodes* : l'API est en lecture seule, tout sauf GET/HEAD est bloqué.

```
Expression : (http.host eq "api.jeremiepatot.fr"
              and http.request.method ne "GET"
              and http.request.method ne "HEAD")
Action : Block
```

Règle 3 (optionnelle) — restreindre au périmètre de la beta :

```
Expression : (http.host eq "api.jeremiepatot.fr"
              and ip.geoip.country ne "FR" and ip.geoip.country ne "CH")
Action : Block
```

**Security → WAF → Rate limiting rules** (1 règle offerte)

```
Expression : (http.host eq "api.jeremiepatot.fr")
Compteur   : 300 requêtes / 1 minute, par IP
Action     : Block pendant 60 s
```

Calibrage, mesuré sur le code client : `AppFeature.pollInterval` vaut **30 s** et
chaque tick déclenche 3 appels par trajet suivi (trip updates, position,
alertes). Un testeur sur un trajet ≈ 6 req/min, avec plusieurs trajets ouverts
20 à 40 req/min. La marge jusqu'à 300 est volontaire : **les opérateurs mobiles
français font du CGNAT**, donc plusieurs testeurs peuvent partager une même IP
publique. Un scraping abusif, lui, se compte en milliers de req/min et reste
bloqué. Regarder *Security → Events* après quelques jours avant de resserrer.

**Caching** — l'API est authentifiée, Cloudflare ne cache rien par défaut avec
un header `Authorization`. Ne rien changer.

---

## 5. Pointer l'app iOS sur le domaine

`APIConfiguration.baseURL` lit déjà la clé `RAILMAP_API_URL` de l'`Info.plist`.
Dans Xcode, cible `RailMapiOS` :

1. *Build Settings* → *User-Defined* → ajouter `RAILMAP_API_URL`
   - Debug : `http://127.0.0.1:8080`
   - Release : `https://api.jeremiepatot.fr`
2. *Info.plist* → ajouter la clé `RAILMAP_API_URL` = `$(RAILMAP_API_URL)`.
3. Supprimer toute exception ATS (`NSAllowsArbitraryLoads`,
   `NSExceptionDomains` sur localhost) du build Release — le domaine est en
   HTTPS/TLS 1.3, ATS passe sans dérogation.
4. Archiver et pousser sur TestFlight.

---

## 5 bis. Rafraîchissement quotidien des GTFS statiques

Il n'y a **aucune planification dans l'API** : `FeedManager.getFeed` retélécharge
paresseusement, à la première requête qui suit l'expiration (24 h pour les
sources SNCF). Sans préchauffage, c'est donc un testeur au hasard qui déclenche
l'ingestion complète — et comme Cloudflare coupe à 100 s, il reçoit une
**erreur 524**, pas une attente.

**Coût réel, mesuré le 13/08/2026 sur le Pi 5 :** `sncf-ter` prend **196 s**,
puis `sncf-tgv` et `sncf-intercites` répondent en **2 ms**. Les trois `DataSource`
SNCF de LocomoSwift pointent en effet sur le même ZIP
(`Export_OpenData_SNCF_GTFS_NewTripId.zip`) et `FeedManager` déduplique son cache
par URL : **un seul téléchargement couvre les trois**. Budget quotidien ≈ 3 min 20.

Piège du cron naïf : `lastUpdate` est horodaté à la **fin** du téléchargement. Une
tâche quotidienne à 04:00 dont l'ingestion finit à 04:15 trouvera le lendemain un
feed vieux de 23 h 45 seulement, jugé encore frais — le rafraîchissement n'aurait
donc lieu qu'un jour sur deux. D'où le redémarrage du conteneur avant le
préchauffage : le cache étant en mémoire, le vider force le téléchargement.

Fichiers : `Scripts/warm-feeds.sh`, `deploy/railmap-warmup.service`,
`deploy/railmap-warmup.timer`.

Installation sur le Pi :

```bash
cd ~/RailMapAPI && git pull && chmod +x Scripts/warm-feeds.sh
sudo cp deploy/railmap-warmup.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now railmap-warmup.timer
systemctl list-timers railmap-warmup --no-pager
```

Test immédiat (~3 min 20 au total) :

```bash
sudo systemctl start railmap-warmup.service
journalctl -u railmap-warmup -f
```

Le service vise `127.0.0.1:8090` en direct, **jamais** l'URL publique : le
plafond de 100 s de Cloudflare rendrait le préchauffage impossible.

---

## 6. Points de vigilance pour la beta

- **Le token est extractible de l'IPA.** `APIKeys.railmapToken` est compilé en
  clair dans le binaire ; n'importe quel testeur peut le sortir. Le vrai rempart
  est le rate limiting Cloudflare. Prévoir la rotation : `API_AUTH_TOKENS`
  accepte une liste séparée par des virgules, donc ajouter le nouveau token,
  livrer un build, puis retirer l'ancien.
- **Timeout 100 s au bord Cloudflare** (erreur 524, non ajustable en Free). La
  chaîne de fallback shapes (OSRM → Overpass) peut le dépasser à froid.
  Préchauffer le cache avant d'ouvrir la beta.
- **Le NVMe est à 99 %** (39 Go libres sur 3,6 To). L'usure n'est pas un souci —
  c'est du NVMe, et le data-root Docker y est déjà — mais la marge l'est.
  Surveiller `df -h /mnt/ssd` : un disque plein, c'est le build qui échoue et le
  démon Docker qui se bloque.
- **Pas de volume pour `db.sqlite`, volontairement.** La base vit dans la couche
  éphémère du conteneur et repart de zéro à chaque `docker compose up`. C'est
  cohérent avec l'état du code : `FeedManager.getFeed` **contourne le rechargement
  SQLite** (correctif A, cf. commentaire à `Sources/App/FeedManager.swift:52`), donc
  persister la base n'éviterait pas la ré-ingestion — elle ne ferait que remplir le
  disque. Conséquence pratique : **tout redémarrage du conteneur repart sur un
  cache froid**, ~3 min 20 d'ingestion avant que les tracés soient bons. À ne pas
  faire pendant la beta. Le jour où le correctif B atterrit, ajouter un bind mount
  vers `/mnt/ssd/railmap/` deviendra utile.
- **Reboot du Pi** : `restart: unless-stopped` sur le conteneur +
  `systemctl enable cloudflared` couvrent le cas. Tester un `sudo reboot` et
  revérifier `/hello` avant d'ouvrir la beta.
- **Surveillance** : `journalctl -u cloudflared -f` côté Pi, et
  *Cloudflare → Analytics → Traffic* pour voir les erreurs 5xx/524.
