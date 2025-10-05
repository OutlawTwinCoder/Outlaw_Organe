# Outlaw_OrganHarvest

Missions illégales de prélèvement d'organes sur des PNJ aléatoires, avec vente au dealer.

## Dépendances
- ESX Legacy (`es_extended`)
- `ox_lib`
- `ox_target`
- `ox_inventory`
- (optionnel) `oxmysql` si besoin d'autres scripts

## Installation
1. Place le dossier **Outlaw_OrganHarvest** dans ton répertoire `resources`.
2. Ajoute à ton `server.cfg` **après** `ox_lib`, `ox_target`, `ox_inventory`, `es_extended` :
   ```cfg
   ensure Outlaw_OrganHarvest
   ```
3. Ouvre `config.lua` et :
   - remplace `Config.DiscordWebhook` avec ton URL.
   - vérifie `Config.UseBlackMoney` (true = black_money, false = cash).
4. Importe le fichier `sql/organ_stats.sql` pour créer la table de suivi de réputation.

## Items (ox_inventory)
Tu dois déclarer les items suivants dans `ox_inventory/data/items.lua` (ou fichier équivalent) :

```lua
-- OUTLAW ORGAN HARVEST ITEMS
['scalpel']       = { label = 'Scalpel', weight = 50, stack = true, close = true, description = 'Instrument chirurgical' },
['scalpel_pro']   = { label = 'Scalpel pro', weight = 55, stack = true, close = true, description = 'Affûté pour un travail propre' },
['scalpel_honed'] = { label = 'Scalpel affûté', weight = 55, stack = true, close = true, description = 'Réservé aux vétérans du marché noir' },
['rein']          = { label = 'Rein', weight = 200, stack = true, close = true },
['crane']         = { label = 'Crâne', weight = 300, stack = true, close = true },
['pied']          = { label = 'Pied', weight = 250, stack = true, close = true },
['yeux']          = { label = 'Yeux', weight = 80, stack = true, close = true },
['organe']        = { label = 'Organe', weight = 150, stack = true, close = true },
['coeur']         = { label = 'Cœur', weight = 120, stack = true, close = true },
['os']            = { label = 'Os', weight = 60, stack = true, close = true },
```

> ⚠️ Les items **doivent exister** côté `ox_inventory`, sinon rien ne sera ajouté/retiré.

## Fonctionnement
- Parle au **PNJ Mission** pour recevoir une **cible** (ped aléatoire) dans une zone.
- Approche la cible et utilise l’option **Prélever un organe** (besoin d’un **scalpel**).
- Une fois l’organe obtenu, rends-toi au **Dealer** pour **vendre** tes organes.
- **Cooldown** configurable entre deux missions (par joueur).

## Commande utilitaire
- `/organreset` : réinitialise ta mission et le cooldown (utile en test).

## Conseils
- Tu peux déplacer les PNJ (Mission/Dealer) et les zones dans `config.lua`.
- Ajuste les **prix** dans `Config.ItemDetails`.
- Le script envoie des **logs** sur Discord si `Config.DiscordWebhook` est rempli.
- Les PNJ dealers gèrent désormais la **réputation** du vendeur, la progression des contrats et l'accès aux **scalpels améliorés** via un menu ox_lib.
