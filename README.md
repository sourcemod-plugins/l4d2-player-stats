# **A Simple Player Statistics Plugin for Left 4 Dead 2**

## Installation



## Usage



## ConVars

| Name                    | Description                                                  | Default value | Min Value | Max Value |
| ----------------------- | ------------------------------------------------------------ | :------------ | --------- | --------- |
| pstats_enabled          | Enable/Disable this plugin                                   | 1             | 0         | 1         |
| pstats_debug_enabled    | Enable debug messages                                        | 0             | 0         | 1         |
| pstats_versus_exclusive | If set, the plugin will only work for versus gamemodes       | 1             | 0         | 1         |
| pstats_record_bots      | Sets whether we should record bots. By default only human players are recorded. | 0             | 0         | 1         |
| pstats_menu_timeout     | The timeout value for the player stats panel                 | 30 (seconds)  | 3         | 9999      |
| pstats_max_top_players  | The max top N players to display                             | 10            | 10        | 50        |

## Commands

| Name             | Description                                                  | Parameters | Parameter Description                  |
| ---------------- | ------------------------------------------------------------ | ---------- | -------------------------------------- |
| sm_rank          | Display the current stats & ranking of the requesting player. A panel will be displayed to the player. | None       | None                                   |
| sm_top           | Display the top N players. A menu panel will be displayed to the requesting player | <number>   | The number of players to be displayed. |
| sm_topig         | Display the ranks of the players currently playing in the server. A menu panel will be displayed to the requesting player. | <number>   | The number of players to be displayed. |
| sm_pstats_reload | Reloads plugin configuration. This is useful if you have modified the playerstats.cfg file. 'This command also synchronizes the modifier values set from the configuration file to the database. | None       | None                                   |

