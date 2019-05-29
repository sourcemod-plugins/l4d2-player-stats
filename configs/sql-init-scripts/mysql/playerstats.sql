/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET NAMES utf8 */;
/*!50503 SET NAMES utf8mb4 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;

CREATE DATABASE IF NOT EXISTS `playerstats` /*!40100 DEFAULT CHARACTER SET utf8 */;
USE `playerstats`;

DELIMITER //
CREATE FUNCTION `APPLY_MODIFIER`(
	`name` VARCHAR(50),
	`value` INT
) RETURNS double
BEGIN
	DECLARE modifier FLOAT;
	
	SELECT s.modifier INTO modifier FROM STATS_SKILLS s WHERE s.name = name;
	
	IF modifier IS NULL 
	THEN
		SELECT 1.0 INTO modifier;
	END IF;
		
	RETURN value * modifier;
END//
DELIMITER ;

CREATE TABLE IF NOT EXISTS `STATS_PLAYERS` (
  `steam_id` varchar(64) NOT NULL,
  `last_known_alias` varchar(255) DEFAULT NULL,
  `last_join_date` timestamp NULL DEFAULT current_timestamp(),
  `survivor_killed` int(10) unsigned NOT NULL DEFAULT 0,
  `survivor_incapped` int(10) unsigned DEFAULT 0,
  `infected_killed` int(10) unsigned NOT NULL DEFAULT 0,
  `infected_headshot` int(10) unsigned NOT NULL DEFAULT 0,
  `create_date` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`steam_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `STATS_SKILLS` (
  `name` varchar(50) NOT NULL,
  `modifier` float DEFAULT NULL,
  `update_date` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `STATS_VW_PLAYER_RANKS` (
	`steam_id` VARCHAR(64) NOT NULL COLLATE 'latin1_swedish_ci',
	`last_known_alias` VARCHAR(255) NULL COLLATE 'latin1_swedish_ci',
	`last_join_date` TIMESTAMP NULL,
	`survivor_killed` INT(10) UNSIGNED NOT NULL,
	`survivor_incapped` INT(10) UNSIGNED NULL,
	`infected_killed` INT(10) UNSIGNED NOT NULL,
	`infected_headshot` INT(10) UNSIGNED NOT NULL,
	`total_points` DOUBLE(19,2) NULL,
	`rank_num` BIGINT(21) NOT NULL,
	`create_date` TIMESTAMP NOT NULL
) ENGINE=MyISAM;

DROP TABLE IF EXISTS `STATS_VW_PLAYER_RANKS`;
CREATE VIEW `STATS_VW_PLAYER_RANKS` AS select `b`.`steam_id` AS `steam_id`,`b`.`last_known_alias` AS `last_known_alias`,`b`.`last_join_date` AS `last_join_date`,`b`.`survivor_killed` AS `survivor_killed`,`b`.`survivor_incapped` AS `survivor_incapped`,`b`.`infected_killed` AS `infected_killed`,`b`.`infected_headshot` AS `infected_headshot`,round(`b`.`total_points`,2) AS `total_points`,`b`.`rank_num` AS `rank_num`,`b`.`create_date` AS `create_date` from (select `s`.`steam_id` AS `steam_id`,`s`.`last_known_alias` AS `last_known_alias`,`s`.`last_join_date` AS `last_join_date`,`s`.`survivor_killed` AS `survivor_killed`,`s`.`survivor_incapped` AS `survivor_incapped`,`s`.`infected_killed` AS `infected_killed`,`s`.`infected_headshot` AS `infected_headshot`,`APPLY_MODIFIER`('survivor_incapped',`s`.`survivor_incapped`) + `APPLY_MODIFIER`('survivor_killed',`s`.`survivor_killed`) + `APPLY_MODIFIER`('infected_killed',`s`.`infected_killed`) + `APPLY_MODIFIER`('infected_headshot',`s`.`infected_headshot`) AS `total_points`,row_number() over ( order by `s`.`survivor_incapped` + `s`.`survivor_killed` + `s`.`infected_headshot` + `s`.`infected_killed` desc,`s`.`create_date`) AS `rank_num`,`s`.`create_date` AS `create_date` from `playerstats`.`STATS_PLAYERS` `s`) `b`;

/*!40101 SET SQL_MODE=IFNULL(@OLD_SQL_MODE, '') */;
/*!40014 SET FOREIGN_KEY_CHECKS=IF(@OLD_FOREIGN_KEY_CHECKS IS NULL, 1, @OLD_FOREIGN_KEY_CHECKS) */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
