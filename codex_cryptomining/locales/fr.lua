Locales = Locales or {}

Locales['fr'] = {
    -- generique
    ['not_ready'] = 'Le reseau crypto demarre encore, reessaie dans un instant.',
    ['no_access'] = 'Tu n as pas acces a cet entrepot.',
    ['not_owner'] = 'Seul le proprietaire peut faire ca.',
    ['invalid_action'] = 'Action invalide.',
    ['too_far'] = 'Tu es trop loin.',
    ['no_money'] = 'Tu n as pas assez d argent.',
    ['no_space'] = 'Tu n as pas assez de place dans ton inventaire.',
    ['busy'] = 'Patiente un instant.',
    ['cancelled'] = 'Annule.',
    ['failed'] = 'Une erreur est survenue.',

    -- entrepot
    ['warehouse_bought'] = 'Tu as achete %s pour %s.',
    ['warehouse_sold'] = 'Tu as vendu %s pour %s.',
    ['warehouse_owned'] = 'Cet entrepot a deja un proprietaire.',
    ['warehouse_limit'] = 'Tu possedes deja le nombre maximum d entrepots.',
    ['warehouse_locked'] = 'La porte est verrouillee.',
    ['warehouse_enter'] = 'Entrer dans l entrepot',
    ['warehouse_exit'] = 'Sortir de l entrepot',
    ['warehouse_panel'] = 'Terminal de gestion',
    ['warehouse_power'] = 'Tableau electrique',
    ['warehouse_storage'] = 'Stockage GPU',
    ['warehouse_blip'] = 'Entrepot Crypto',
    ['keys_given'] = 'Tu as donne les cles a %s.',
    ['keys_received'] = 'Tu as recu les cles de %s.',
    ['keys_removed'] = 'Tu as retire les cles de %s.',
    ['keys_lost'] = 'Tu as perdu l acces a %s.',
    ['keys_no_player'] = 'Aucun joueur a proximite.',

    -- rigs
    ['rig_installed'] = 'Rig de minage installe.',
    ['rig_removed'] = 'Rig de minage demonte.',
    ['rig_full'] = 'Plus aucun emplacement libre dans cet entrepot.',
    ['rig_not_found'] = 'Ce rig n existe pas.',
    ['rig_not_empty'] = 'Retire tous les GPU avant de demonter le rig.',
    ['rig_broken'] = 'Ce rig est casse, repare le d abord.',
    ['rig_repaired'] = 'Rig repare (%s%%).',
    ['rig_disaster'] = 'Un rig est tombe en panne dans %s !',
    ['gpu_installed'] = 'GPU installe.',
    ['gpu_removed'] = 'GPU retire.',
    ['gpu_full'] = 'Ce rig est deja plein.',
    ['gpu_none'] = 'Il n y a aucun GPU dans ce rig.',
    ['gpu_missing'] = 'Tu n as pas de GPU.',
    ['cpu_installed'] = 'CPU ameliore au niveau %s.',
    ['cpu_max'] = 'Ce rig a deja le meilleur CPU.',
    ['cooler_installed'] = 'Refroidissement ameliore au niveau %s.',
    ['cooler_max'] = 'Ce rig a deja le meilleur refroidissement.',
    ['repairkit_missing'] = 'Il te faut un kit de reparation.',

    -- electricite
    ['power_cut'] = 'Le courant de %s a ete coupe, paie la facture.',
    ['power_restored'] = 'Courant retabli dans %s.',
    ['power_paid'] = 'Tu as paye %s d electricite.',
    ['power_nothing'] = 'Il n y a rien a payer.',
    ['power_off'] = 'Le courant est coupe.',

    -- marche
    ['market_sold'] = 'Tu as vendu %s BTC pour %s.',
    ['market_empty'] = 'Tu n as pas autant de BTC.',
    ['market_price'] = 'Le Bitcoin vaut %s.',
    ['storage_full'] = 'Le portefeuille de cet entrepot est plein, vends tes BTC.',

    -- boutiques
    ['shop_bought'] = 'Tu as achete %sx %s pour %s.',
    ['shop_sold'] = 'Tu as vendu %sx %s pour %s.',
    ['shop_no_item'] = 'Tu n as pas cet objet.',
    ['shop_quantity'] = 'Quantite invalide.',
    ['techshop_target'] = 'TechShop',
    ['blackmarket_target'] = 'Marche noir',
    ['informant_target'] = 'Informateur',
    ['broker_target'] = 'Agent immobilier',

    -- informateur
    ['informant_bought'] = 'La position de %s a ete marquee sur ton GPS.',
    ['informant_none'] = 'Aucune cible interessante pour le moment.',
    ['informant_cooldown'] = 'Reviens dans %s minutes.',

    -- braquage
    ['robbery_started'] = 'Tu es entre dans l entrepot.',
    ['robbery_police'] = 'Tu n as pas assez de contacts en ville pour le moment.',
    ['robbery_busy'] = 'Trop de coups sont en cours en ce moment.',
    ['robbery_cooldown'] = 'Tu dois te faire oublier pendant %s minutes.',
    ['robbery_warehouse_cooldown'] = 'Cet entrepot a deja ete visite recemment.',
    ['robbery_empty'] = 'Il n y a rien a voler ici.',
    ['robbery_own'] = 'Tu ne peux pas braquer ton propre entrepot.',
    ['robbery_need_lockpick'] = 'Il te faut un crochet.',
    ['robbery_need_usb'] = 'Il te faut une cle USB de hack.',
    ['robbery_lockpick_broken'] = 'Ton crochet a casse.',
    ['robbery_failed'] = 'Tu as echoue.',
    ['robbery_looted'] = 'Tu as vole %sx GPU.',
    ['robbery_nothing_left'] = 'Ce rig est vide.',
    ['robbery_owner_alert'] = 'Alarme : quelqu un est entre dans %s !',
    ['robbery_finished'] = 'Le coup est termine, degage.',
    ['robbery_timeout'] = 'Tu as mis trop de temps.',

    -- cibles
    ['target_rig'] = 'Rig de minage',
    ['target_rig_loot'] = 'Voler les GPU',
    ['target_door'] = 'Forcer la porte',
    ['press_to_open'] = 'Appuie sur ~INPUT_CONTEXT~ pour %s',

    -- admin
    ['admin_only'] = 'Tu n as pas le droit d utiliser cette commande.',
    ['admin_reset'] = 'L entrepot %s a ete reinitialise.',
    ['admin_unknown'] = 'Entrepot inconnu.',
    ['admin_usage'] = 'Utilisation : /%s [price|reset|info|setowner] ...'
}
