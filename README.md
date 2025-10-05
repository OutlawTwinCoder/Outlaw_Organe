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

## Items (ox_inventory)
Tu dois déclarer les items suivants dans `ox_inventory/data/items.lua` (ou fichier équivalent) :

> 📄 Un fichier prêt à copier est disponible dans [`item_data/ox_inventory.lua`](item_data/ox_inventory.lua).

```lua
-- OUTLAW ORGAN HARVEST ITEMS
['scalpel'] = { label = 'Scalpel', weight = 50, stack = true, close = true, description = 'Instrument chirurgical' },
['scalpel_pro'] = { label = 'Scalpel Pro', weight = 50, stack = true, close = true, description = 'Affûtage renforcé' },
['scalpel_elite'] = { label = 'Scalpel Élite', weight = 50, stack = true, close = true, description = 'Lame personnalisée et équilibrée' },
['surgery_kit'] = { label = 'Kit chirurgical', weight = 150, stack = true, close = true, description = 'Stérilisation et outils à usage unique' },
['rein']    = { label = 'Rein', weight = 200, stack = true, close = true },
['crane']   = { label = 'Crâne', weight = 300, stack = true, close = true },
['pied']    = { label = 'Pied', weight = 250, stack = true, close = true },
['yeux']    = { label = 'Yeux', weight = 80, stack = true, close = true },
['organe']  = { label = 'Organe', weight = 150, stack = true, close = true },
['coeur']   = { label = 'Cœur', weight = 120, stack = true, close = true },
['os']      = { label = 'Os', weight = 60, stack = true, close = true },
```

> ⚠️ Les items **doivent exister** côté `ox_inventory`, sinon rien ne sera ajouté/retiré.

## Fonctionnement
- Parle au **PNJ Mission** pour recevoir une **cible** (ped aléatoire) dans une zone.
- Approche la cible et utilise l’option **Prélever un organe** (besoin d’un **scalpel**).
- Une fois l’organe obtenu, rends-toi au **Dealer** pour **vendre** tes organes ou accéder au nouveau **menu réputation**.
- Les ventes de **qualité** améliorent ta réputation et débloquent des commandes rares (comme le **cœur**) et des bonus sur le prix de base.
- Utilise le menu du dealer pour acheter du matériel, suivre tes statistiques et **améliorer ton scalpel** si tu as les livraisons requises.
- **Cooldown** configurable entre deux missions (par joueur).

## Réputation du dealer
- Chaque organe vendu octroie des points de réputation en fonction de la qualité et du type de pièce.
- Des **paliers** augmentent automatiquement le multiplicateur de prix et débloquent de nouveaux organes dans la rotation des missions.
- Le menu du dealer affiche :
  - Les contrats terminés, la qualité moyenne et la meilleure qualité livrée.
  - Le cumul de chaque organe vendu et les seuils de déblocage.
  - Les commandes rares et leur statut.
- Certaines améliorations (ex: **Scalpel Élite**) nécessitent un certain niveau de réputation **et** des quantités livrées spécifiques pour être accessibles.

## Tableau des missions
- Parle au donneur de missions pour ouvrir l'interface **Outlaw** dédiée (même style que le dealer).
- Chaque type de contrat (os, pieds, crânes, etc.) possède des prérequis en **livraisons cumulées** et en **réputation**.
- Tant qu'un contrat n'est pas débloqué, l'organe correspondant ne peut pas apparaître dans les récoltes aléatoires.
- Une fois un palier atteint, tu peux acheter un **contrat ciblé** (ex: « Commande rénale ») qui force l'organe obtenu et impose un délai (configurable) pour réussir.
- Après prélèvement de l’organe demandé par un contrat ciblé, utilise l’action **Terminer mission** (depuis le dealer ou le tableau) pour valider la commande sans fermer l’interface.
- Le menu affiche :
  - ta progression sur chaque contrat (barres et pourcentages) ;
  - les bonus de réputation accordés par les contrats spéciaux ;
  - la composition actuelle de la **pool** d'organes disponibles en mission libre.
- Ajuste les paliers, coûts, délais et bonus dans `Config.MissionBoard` (section `Config.MissionBoard.Contracts`).

## Commande utilitaire
- `/organreset` : réinitialise ta mission et le cooldown (utile en test).

## Conseils
- Tu peux déplacer les PNJ (Mission/Dealer) et les zones dans `config.lua`.
- Ajuste les **prix** dans `Config.ItemDetails`.
- Le script envoie des **logs** sur Discord si `Config.DiscordWebhook` est rempli.
