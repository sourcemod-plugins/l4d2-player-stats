### **Simple Player Statistics Plugin for Left 4 Dead 2**

### Features

- This plugin tracks and records player statistics from human players. The following statistics are currently being recorded:

  | Name                | Team     |
  | ------------------- | -------- |
  | Survivors Kils      | Infected |
  | Survivors In capped | Infected |
  | Infected Kills      | Survivor |
  | Infected Headshots  | Survivor |

  

- A customizable connect announce when a player joins displaying the current ranking/steam id/total points of the user. This feature also supports colour coded messages. 

  ![Connect Announce](connect_announce.png)

- A display panel showing the player statistics of a user. This can be triggered by issuing `sm_rank` on the console or by typing `!rank`in chat.

  ![Player Rank](player_rank.png)

- A display panel showing the top N players sorted by their ranking. This feature also allows the the requesting player to be able to view other player's statistics/ranking on the server.

  ![Top N Players](top_players.png)

- A point system is also implemented and can be further customized by modifying the point multipliers from the plugin configuration file (`playerstats.cfg`)

### Installation

Download the [latest](https://github.com/sourcemod-plugins/l4d2-player-stats/archive/master.zip) version from the repository and extract the contents of **l4d2-player-stats-master/** to the root directory of the left 4 dead 2 server installation. 

### Configuration

#### Database Configuration

1. Create and setup the appropriate users/credentials/privileges on your MySQL/MariaDB database system.

2. Import the [provided SQL script](https://github.com/sourcemod-plugins/l4d2-player-stats/blob/master/configs/sql-init-scripts/mysql/playerstats.sql) (under `/configs/sql-init-scripts/mysql/playerstats.sql`\) into your MySQL/MariaDB system.

3. Open `databases.cfg` file from `addons/sourcemod/configs` and add a new section named `playerstats`.

   Example:

   ```
   "playerstats"
   {
   	"host"	    "<ip address>"
   	"driver"    "mysql"
   	"database"  "playerstats"
   	"user"		"<username>"
   	"pass"		"<password>"
   	//"timeout"			"0"
   	//"port"			"0"
   }
   ```

#### Plugin Configuration

The plugin can be further customized through the `playerstats.cfg` file located under `addons/sourcemod/configs/`. The default entries will look like this:

```
"PlayerStats" {
	"StatModifiers" 
	{
		"survivor_killed" 	"1.0"
		"survivor_incapped" "1.0"
		"infected_killed" 	"1.0"
		"infected_headshot" "1.0"
	}
	"PlayerRankPanel" 
	{
		"title"		"► Player Stats ◄"
	}
	"ConnectAnnounce" 
	{
	    "format"	"{N}Player '{G}{last_known_alias}{N}' ({B}{steam_id}{N}) has joined the game ({G}Rank:{N} {i:rank_num}, {G}Points:{N} {f:total_points})"
	}
}
```

Connect Announce Output: 

![Connect Announce Output](connect_announce.png)



> Note: You can reload the configuration with the `sm_pstats_reload` command. Issuing this command will also synchronize the point modifiers on the STATS_MODIFIERS table.



##### Configuration Sections</u>

| Section Name    | Description                                                  |
| --------------- | ------------------------------------------------------------ |
| StatModifiers   | This section contains the point modifiers for the point system. These values affects the total points of the user. For example, if a player has killed 10 special infected by headshot (infected_headshot) and the point modifier is 2.5 the total points for the number of infected headshots would be 25. |
| PlayerRankPanel | This section configures the display panel  of the player statistics/ranking. Currently you will only be able to customize the title of the panel. |
| ConnectAnnounce | This section configures the format of the player connect announce. The formatting rules are explained below. |

#### Connect Announce Formatting Rules

**<u>Colour Tags</u>**

| Tag   | Color                                  |
| ----- | -------------------------------------- |
| {N}   | Default/normal                         |
| {O}   | Orange                                 |
| {R}   | Red                                    |
| {RB}  | Red/Blue                               |
| {B}   | Blue (green if no player on blue team) |
| {BR}  | Blue/Red                               |
| {T}   | Teamcolor                              |
| {L}   | Lightgreen                             |
| {GRA} | Grey (green if no spectator)           |
| {G}   | Green                                  |
| {OG}  | Olive                                  |
| {BLA} | Black                                  |

**<u>Special Tags</u>**

Some tags are prefixed with "d", "i" or "f". These prefixes are necessary to identify the type of the data so the plugin will be able to interpret it correctly when read from the database. 

Tag Prefix

| Prefix | Type                          |
| ------ | ----------------------------- |
| i      | Integer Number                |
| d      | Date/Time                     |
| f      | Decimal/Floating Point Number |

| Tag                   | Description                                         |
| --------------------- | --------------------------------------------------- |
| {steam_id}            | Steam ID                                            |
| {last_known_alias}    | Last known alias or name of the player              |
| {d:last_join_date}    | Last join date on the server                        |
| {i:survivor_killed}   | Number of Survivors Killed (As Infected)            |
| {i:survivor_incapped} | Number of Survivors Incapped (As Infected)          |
| {i:infected_killed}   | Number of Infected Killed (As Survivor)             |
| {i:infected_headshot} | Number of Infected Killed by Headshot (As Survivor) |
| {f:total_points}      | Total Points (Sum of everything)                    |
| {i:rank_num}          | Current Ranking                                     |



------

### ConVars

| Name                    | Description                                                  | Default value | Min Value | Max Value |
| ----------------------- | ------------------------------------------------------------ | :------------ | --------- | --------- |
| pstats_enabled          | Enable/Disable this plugin                                   | 1             | 0         | 1         |
| pstats_debug_enabled    | Enable debug messages                                        | 0             | 0         | 1         |
| pstats_versus_exclusive | If set, the plugin will only work for versus gamemodes       | 1             | 0         | 1         |
| pstats_record_bots      | Sets whether we should record bots. By default only human players are recorded. | 0             | 0         | 1         |
| pstats_menu_timeout     | The timeout value for the player stats panel                 | 30 (seconds)  | 3         | 9999      |
| pstats_max_top_players  | The max top N players to display                             | 10            | 10        | 50        |

### Commands

| Name             | Description                                                  | Parameters | Parameter Description                  |
| ---------------- | ------------------------------------------------------------ | ---------- | -------------------------------------- |
| sm_rank          | Display the current stats & ranking of the requesting player. A panel will be displayed to the player. | None       | None                                   |
| sm_top           | Display the top N players. A menu panel will be displayed to the requesting player | Number     | The number of players to be displayed. |
| sm_ranks         | Display the ranks of the players currently playing in the server. A menu panel will be displayed to the requesting player. | Number     | The number of players to be displayed. |
| sm_pstats_reload | Reloads plugin configuration. This is useful if you have modified the playerstats.cfg file. 'This command also synchronizes the modifier values set from the configuration file to the database. | None       | None                                   |

