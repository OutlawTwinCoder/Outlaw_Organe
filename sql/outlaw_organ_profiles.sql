CREATE TABLE IF NOT EXISTS `outlaw_organ_profiles` (
  `identifier` varchar(60) NOT NULL,
  `reputation` int NOT NULL DEFAULT 0,
  `contracts` int NOT NULL DEFAULT 0,
  `total_quality` int NOT NULL DEFAULT 0,
  `delivered` longtext DEFAULT NULL,
  `upgrades` longtext DEFAULT NULL,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
