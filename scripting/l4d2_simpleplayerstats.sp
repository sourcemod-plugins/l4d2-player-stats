/**
* Simple Player Statistics
* 
* Copyright (C) 2019 
* 
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
* 
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License 
* along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

#include <sourcemod>
#include <sdktools>
#include <smlib>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_AUTHOR "mac & cheese (a.k.a thresh0ld)"
#define PLUGIN_VERSION "1.0.0-alpha"

#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_VALID_HUMAN(%1)		(IS_VALID_CLIENT(%1) && IsClientConnected(%1) && !IsFakeClient(%1))
#define IS_SPECTATOR(%1)        (GetClientTeam(%1) == TEAM_SPECTATOR)
#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == TEAM_SURVIVOR)
#define IS_INFECTED(%1)         (GetClientTeam(%1) == TEAM_INFECTED)
#define IS_VALID_INGAME(%1)     (IS_VALID_CLIENT(%1) && IsClientInGame(%1))
#define IS_VALID_SURVIVOR(%1)   (IS_VALID_INGAME(%1) && IS_SURVIVOR(%1))
#define IS_VALID_INFECTED(%1)   (IS_VALID_INGAME(%1) && IS_INFECTED(%1))
#define IS_VALID_SPECTATOR(%1)  (IS_VALID_INGAME(%1) && IS_SPECTATOR(%1))
#define IS_SURVIVOR_ALIVE(%1)   (IS_VALID_SURVIVOR(%1) && IsPlayerAlive(%1))
#define IS_INFECTED_ALIVE(%1)   (IS_VALID_INFECTED(%1) && IsPlayerAlive(%1))
#define MAX_CLIENTS MaxClients

#define CONFIG_FILE "playerstats.cfg"
#define DB_CONFIG_NAME "playerstats"

#define STATS_STEAM_ID "steam_id"
#define STATS_LAST_KNOWN_ALIAS "last_known_alias"
#define STATS_LAST_JOIN_DATE "last_join_date"
#define STATS_SURVIVOR_KILLED "survivor_killed"
#define STATS_SURVIVOR_INCAPPED "survivor_incapped"
#define STATS_INFECTED_KILLED "infected_killed"
#define STATS_INFECTED_HEADSHOT "infected_headshot"
#define STATS_WITCH_CROWNS "witch_crowns"
#define STATS_TOTAL_POINTS "total_points"
#define STATS_RANK "rank_num"
#define STATS_CREATE_DATE "create_date"

#define DEFAULT_CONFIG_PANEL_TITLE "Player Stats"
#define DEFAULT_CONFIG_ANNOUNCE_FORMAT "{N}Player '{G}{last_known_alias}{N}' ({B}{steam_id}{N}) has joined the game ({G}Rank:{N} {i:rank_num}, {G}Points:{N} {f:total_points})"
#define DEFAULT_TOP_PLAYERS 10
#define DEFAULT_MIN_TOP_PLAYERS 10
#define DEFAULT_MAX_TOP_PLAYERS 50

Database g_hDatabase = null;
StringMap g_mStatModifiers;
bool g_bPlayerInitialized[MAXPLAYERS + 1] = false;
bool g_bInitializing[MAXPLAYERS + 1] = false;
bool g_bShowingRankPanel[MAXPLAYERS + 1] = false;
char g_ConfigPath[PLATFORM_MAX_PATH];
char g_ConfigPanelTitle[255];
char g_ConfigAnnounceFormat[512];

ConVar g_bDebug;
ConVar g_bVersusExclusive;
ConVar g_bEnabled;
ConVar g_bRecordBots;
ConVar g_iStatsMenuTimeout;
ConVar g_iStatsMaxTopPlayers;
ConVar g_sGameMode;

public Plugin myinfo = 
{
	name = "Simple Player Statistics", 
	author = PLUGIN_AUTHOR, 
	description = "Tracks kills, deaths and other special skills", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/sourcemod-plugins/l4d2-player-stats"
};

/**
* Called when the plugin is fully initialized and all known external references are resolved. This is only called once in the lifetime of the plugin, and is paired with OnPluginEnd().
* If any run-time error is thrown during this callback, the plugin will be marked as failed.
*/
public void OnPluginStart()
{
	//Make sure we are on left 4 dead 2!
	if (GetEngineVersion() != Engine_Left4Dead2) {
		SetFailState("This plugin only supports left 4 dead 2!");
		return;
	}
	
	BuildPath(Path_SM, g_ConfigPath, sizeof(g_ConfigPath), "configs/%s", CONFIG_FILE);
	
	char defaultTopPlayerStr[32];
	IntToString(DEFAULT_TOP_PLAYERS, defaultTopPlayerStr, sizeof(defaultTopPlayerStr));
	
	g_bEnabled = CreateConVar("pstats_enabled", "1", "Enable/Disable tracking");
	g_bDebug = CreateConVar("pstats_debug_enabled", "0", "Enable debug messages");
	g_bVersusExclusive = CreateConVar("pstats_versus_exclusive", "1", "If set, stats collection will be exclusive to versus mode only");
	g_bRecordBots = CreateConVar("pstats_record_bots", "0", "Sets whether we should record bots");
	g_iStatsMenuTimeout = CreateConVar("pstats_menu_timeout", "30", "The timeout value for the player stats panel");
	g_iStatsMaxTopPlayers = CreateConVar("pstats_max_top_players", defaultTopPlayerStr, "The max top N players to display", 0, true, float(DEFAULT_MIN_TOP_PLAYERS), true, float(DEFAULT_MAX_TOP_PLAYERS));
	g_sGameMode = FindConVar("mp_gamemode");
	
	if (!InitDatabase()) {
		SetFailState("Could not connect to the database");
	} else {
		Info("Successfully connected to the database");
	}
	
	if (!LoadConfigData()) {
		SetFailState("Problem loading/reading config file: %s", g_ConfigPath);
		return;
	}
	
	RegConsoleCmd("sm_rank", Command_ShowRank, "Display the current stats & ranking of the requesting player. A panel will be displayed to the player.");
	RegConsoleCmd("sm_top", Command_ShowTopPlayers, "Display the top N players. A menu panel will be displayed to the requesting player");
	RegConsoleCmd("sm_topig", Command_ShowTopPlayersInGame, "Display the ranks of the players currently playing in the server. A menu panel will be displayed to the requesting player.");
	RegAdminCmd("sm_pstats_reload", Command_ReloadConfig, ADMFLAG_ROOT, "Reloads plugin configuration. This is useful if you have modified the playerstats.cfg file. 'This command also synchronizes the modifier values set from the configuration file to the database.");
	
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_incapacitated", Event_PlayerIncapped, EventHookMode_Post);
	HookEvent("round_start", Event_OnRoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_OnRoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("witch_killed", Event_WitchKilled, EventHookMode_Post);
	//Note: We use this event instead of OnClientDisconnect because this event does not get fired on map change.
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
	HookEvent("map_transition", Event_MapTransition, EventHookMode_Post);
	HookEvent("player_transitioned", Event_PlayerTransitioned, EventHookMode_Post);
	HookEvent("bot_player_replace", Event_PlayerReplaceBot, EventHookMode_Post);
}

public bool AllowCollectStats() {
	if (g_bEnabled.IntValue <= 0) {
		Debug("Stats collection is currently disabled");
		return false;
	}
	
	char gameMode[255];
	g_sGameMode.GetString(gameMode, sizeof(gameMode));
	if (g_bVersusExclusive.IntValue <= 0)
		return true;
	return StrEqual(gameMode, "versus");
}

public Action Command_ReloadConfig(int client, int args) {
	if (!LoadConfigData()) {
		LogAction(client, -1, "Failed to reload plugin configuration file");
		SetFailState("Problem loading/reading config file: %s", g_ConfigPath);
		return Plugin_Handled;
	}
	
	LogAction(client, -1, "Plugin configuration reloaded successfully");
	PrintToChat(client, "Plugin configuration reloaded successfully");
	
	if (g_bDebug.IntValue > 0) {
		PlayerConnectAnnounce(client);
	}
	return Plugin_Handled;
}

public bool LoadConfigData() {
	KeyValues kv = new KeyValues("PlayerStats");
	
	if (!kv.ImportFromFile(g_ConfigPath)) {
		return false;
	}
	
	//Re-initialize the modifier map
	if (g_mStatModifiers == null) {
		Debug("Re-initializing map");
		g_mStatModifiers = new StringMap();
	}
	
	Info("Parsing configuration file: %s", g_ConfigPath);
	
	Debug("Processing Stat Modifiers");
	if (kv.JumpToKey("StatModifiers", false))
	{
		if (kv.GotoFirstSubKey(false))
		{
			do
			{
				char key[255];
				float value;
				kv.GetSectionName(key, sizeof(key));
				value = kv.GetFloat(NULL_STRING, 1.0);
				
				Debug("Modifier: %s = %f", key, value);
				g_mStatModifiers.SetValue(key, value, true);
				
				//Synchronize values to SKILL_STATS table
				SyncStatModifiers(key, value);
			}
			while (kv.GotoNextKey(false));
		}
		kv.GoBack();
	} else {
		Error("Missing config key 'StatModifiers'");
		delete kv;
		return false;
	}
	kv.GoBack();
	
	Debug("Processing Player Rank Panel");
	if (!kv.JumpToKey("PlayerRankPanel"))
	{
		Error("Missing config key 'PlayerRankPanel'");
		delete kv;
		return false;
	}
	
	kv.GetString("title", g_ConfigPanelTitle, sizeof(g_ConfigPanelTitle));
	
	if (strcmp(g_ConfigPanelTitle, "", false) == 0) {
		Debug("Config stats panel title is empty. Using default");
		FormatEx(g_ConfigPanelTitle, sizeof(g_ConfigPanelTitle), DEFAULT_CONFIG_PANEL_TITLE);
	}
	
	kv.GoBack();
	
	Debug("Processing Connect Announce");
	if (!kv.JumpToKey("ConnectAnnounce")) {
		Error("Missing config key 'ConnectAnnounce'");
		delete kv;
		return false;
	}
	
	kv.GetString("format", g_ConfigAnnounceFormat, sizeof(g_ConfigAnnounceFormat));
	
	if (strcmp(g_ConfigAnnounceFormat, "", false) == 0) {
		Debug("> Connect announce format is empty. Using default");
		FormatEx(g_ConfigAnnounceFormat, sizeof(g_ConfigAnnounceFormat), DEFAULT_CONFIG_ANNOUNCE_FORMAT);
	}
	
	Info("Loaded config : Processed Modifiers %d", g_mStatModifiers.Size);
	Info("Loaded config : Title = %s", g_ConfigPanelTitle);
	Info("Loaded config : Connect Announce Format = %s", g_ConfigAnnounceFormat);
	
	delete kv;
	return true;
}

public void SyncStatModifiers(const char[] key, float value) {
	if (StringBlank(key)) {
		Debug("No key specified. Skipping sync");
		return;
	}
	
	int len = strlen(key) * 2 + 1;
	char[] qKey = new char[len];
	if (!g_hDatabase.Escape(key, qKey, len)) {
		Debug("Could not escape string '%s'", key);
		return;
	}
	
	char query[512];
	FormatEx(query, sizeof(query), "INSERT INTO STATS_SKILLS (name, modifier, update_date) VALUES ('%s', %f, current_timestamp()) ON DUPLICATE KEY UPDATE modifier = %f, update_date = current_timestamp()", qKey, value, value);
	
	DataPack pack = new DataPack();
	pack.WriteString(key);
	pack.WriteFloat(value);
	
	Info("Synchronizing stat entry (%s = %f) to database", key, value);
	g_hDatabase.Query(TQ_SyncStatModifiers, query, pack);
}

public void TQ_SyncStatModifiers(Database db, DBResultSet results, const char[] error, any data) {
	if (results == null) {
		LogError("TQ_SyncStatModifiers :: Query failed (Reason: %s)", error);
		Debug("TQ_SyncStatModifiers :: Query failed  (Reason: %s)", error);
		return;
	}
	
	DataPack pack = data;
	char name[255];
	float modifier;
	
	pack.Reset();
	pack.ReadString(name, sizeof(name));
	modifier = pack.ReadFloat();
	
	if (results.AffectedRows > 0) {
		Info("SYNC STATS :: Successfully synchronized skill entry (name: %s, modifier: %f)", name, modifier);
	} else {
		Info("SYNC STATS :: Nothing was updated (name: '%s', modifier: %f)", name, modifier);
	}
}

public Action Event_PlayerReplaceBot(Event event, const char[] name, bool dontBroadcast) {
	int botId = event.GetInt("bot");
	int userId = event.GetInt("player");
	
	int botClientId = GetClientOfUserId(botId);
	int clientId = GetClientOfUserId(userId);
	
	Debug("Player %N has replaced bot %N", clientId, botClientId);
	
	return Plugin_Continue;
}

public Action Event_PlayerTransitioned(Event event, const char[] name, bool dontBroadcast) {
	int userId = event.GetInt("userid");
	int clientId = GetClientOfUserId(userId);
	Debug("Player has transitioned to first person view = %N", clientId);
	
	char steamId[128];
	GetClientAuthId(clientId, AuthId_Steam2, steamId, sizeof(steamId));
	
	ShowPlayerRankPanel(clientId, steamId);
	return Plugin_Continue;
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	char reason[512];
	char playerName[255];
	char networkId[255];
	
	int userId = event.GetInt("userid");
	int clientId = GetClientOfUserId(userId);
	
	event.GetString("name", playerName, sizeof(playerName));
	event.GetString("reason", reason, sizeof(reason));
	event.GetString("networkid", networkId, sizeof(networkId));
	int isBot = event.GetInt("bot");
	
	if (!IS_VALID_CLIENT(clientId) || IsFakeClient(clientId))
		return Plugin_Continue;
	
	Debug("(EVENT => %s): name = %s, reason = %s, id = %s, isBot = %i, clientid = %i", name, playerName, reason, networkId, isBot, clientId);
	Debug("Resetting client flags for player %N", clientId);
	
	g_bPlayerInitialized[clientId] = false;
	
	return Plugin_Continue;
}

public Action Event_MapTransition(Event event, const char[] name, bool dontBroadcast) {
	Debug("EVENT_MAP_TRANSITION");
}

/**
* Called when the plugin is about to be unloaded.
* It is not necessary to close any handles or remove hooks in this function. SourceMod guarantees that plugin shutdown automatically and correctly releases all resources.
*/
public void OnPluginEnd() {
	Debug("================================= OnPluginEnd =================================");
}

/**
* Check if player has been initialized (existing record in database)
*
* @return true if the player record has been initialized
*/
public bool isInitialized(int client) {
	return g_bPlayerInitialized[client];
}

/**
* Function to check if we are on the final level of the versus campaign
*
* @return true if the current map is the final map of the versus campaign
*/
stock bool IsFinalMap()
{
	return (FindEntityByClassname(-1, "info_changelevel") == -1
		 && FindEntityByClassname(-1, "trigger_changelevel") == -1);
}

/**
* Function to check if we still have a next level after the current
* 
* @return true if we still have next map after the current
*/
stock bool HasNextMap()
{
	return (FindEntityByClassname(-1, "info_changelevel") >= 0
		 || FindEntityByClassname(-1, "trigger_changelevel") >= 0);
}

/**
* Called when the map has loaded, servercfgfile (server.cfg) has been executed, and all plugin configs are done executing. 
* This is the best place to initialize plugin functions which are based on cvar data.
*/
public void OnConfigsExecuted() {
	//If the plugin has been reloaded, we re-initialize the players. This does not apply during map transition
	if (GetHumanPlayerCount() > 0) {
		Debug("OnConfigsExecuted() :: Initializing players");
		InitializePlayers();
	}
	else {
		Debug("OnConfigsExecuted() :: Skipped player initialization. No available players");
	}
}

/**
* Called when a client receives an auth ID. The state of a client's authorization as an admin is not guaranteed here. 
* Use OnClientPostAdminCheck() if you need a client's admin status.
* This is called by bots, but the ID will be "BOT".
*/
public void OnClientAuthorized(int client, const char[] auth) {
	//Ignore bots
	if (!IS_VALID_HUMAN(client))
		return;
	Debug("OnClientAuthorized(%N) = %s", client, auth);
	InitializePlayer(client, !isInitialized(client));
}

/**
* Called once a client successfully connects. This callback is paired with OnClientDisconnect.
*/
public void OnClientConnected(int client) {
	if (!IS_VALID_HUMAN(client))
		return;
	Debug("OnClientConnected(%N)", client);
}

/**
* Called when a client is entering the game.
* Whether a client has a steamid is undefined until OnClientAuthorized is called, which may occur either before or after OnClientPutInServer. 
* Similarly, use OnClientPostAdminCheck() if you need to verify whether connecting players are admins.
* GetClientCount() will include clients as they are passed through this function, as clients are already in game at this point.
*/
public void OnClientPutInServer(int client) {
	if (!IS_VALID_HUMAN(client))
		return;
	Debug("OnClientPutInServer(%N)", client);
}

/**
* Called once a client is authorized and fully in-game, and after all post-connection authorizations have been performed.
* This callback is guaranteed to occur on all clients, and always after each OnClientPutInServer() call.
*/
public void OnClientPostAdminCheck(int client) {
	if (!IS_VALID_HUMAN(client))
		return;
	if (isInitialized(client)) {
		Debug("Player has not yet been initialized. Skipping connect announce for '%N'", client);
	}
	Debug("OnClientPostAdminCheck(%N = %i)", client, client);
	PlayerConnectAnnounce(client);
}

/**
* Called when a client is disconnecting from the server.
*/
public void OnClientDisconnect(int client) {
	if (!IS_VALID_HUMAN(client))
		return;
	Debug("OnClientDisconnect(%N)", client);
}

/**
* Called when the map is loaded.
*/
public void OnMapStart() {
	Debug("================================= OnMapStart =================================");
}

/**
* Called right before a map ends.
*/
public void OnMapEnd() {
	if (HasNextMap()) {
		Debug("================================= OnMapEnd ================================= (CHANGING LEVELS)");
	} else {
		Debug("================================= OnMapEnd ================================= (NOT CHANGING LEVEL)");
	}
}

/**
* Callback for sm_topig command
*/
public Action Command_ShowTopPlayersInGame(int client, int args) {
	//TODO
	return Plugin_Handled;
}

/**
* Callback method for the sm_top console command
*/
public Action Command_ShowTopPlayers(int client, int args) {
	int maxPlayers = (g_iStatsMaxTopPlayers.IntValue <= 0) ? DEFAULT_MAX_TOP_PLAYERS : g_iStatsMaxTopPlayers.IntValue;
	
	if (args >= 1) {
		char arg[255];
		GetCmdArg(1, arg, sizeof(arg));
		if (!String_IsNumeric(arg)) {
			PrintToChat(client, "Argument must be numeric: %s", arg);
			return Plugin_Handled;
		}
		maxPlayers = StringToInt(arg);
		
		//Check bounds
		if (maxPlayers < DEFAULT_MIN_TOP_PLAYERS) {
			maxPlayers = DEFAULT_MIN_TOP_PLAYERS;
		}
		if (maxPlayers > DEFAULT_MAX_TOP_PLAYERS)
			maxPlayers = DEFAULT_MAX_TOP_PLAYERS;
	}
	
	Debug("Displaying top %i players", maxPlayers);
	ShowTopPlayersRankPanel(client, maxPlayers);
	
	return Plugin_Handled;
}

/**
* Callback method for the command show rank
*/
public Action Command_ShowRank(int client, int args) {
	
	if (!IS_VALID_HUMAN(client)) {
		Error("Client '%N' is not valid. Skipping show rank", client);
		return Plugin_Handled;
	}
	
	char steamId[128];
	if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId))) {
		Error("Unable to retrieve a valid steam id from client %N", client);
	}
	ShowPlayerRankPanel(client, steamId);
	return Plugin_Handled;
}

/**
* Display the Player Rank Panel to the target user
*
* @param client The target client index
* @param max The maximum number of players to be displayed on the rank panel. Note: The upper and lower limits are capped between DEFAULT_MIN_TOP_PLAYERS and DEFAULT_MAX_TOP_PLAYERS.
*/
void ShowTopPlayersRankPanel(int client, int max = DEFAULT_MAX_TOP_PLAYERS) {
	if (!IS_VALID_CLIENT(client) || IsFakeClient(client)) {
		Debug("Skipping show stats. Not a valid client");
		return;
	}
	
	char steamId[128];
	GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId));
	
	int len = strlen(steamId) * 2 + 1;
	char[] qSteamId = new char[len];
	SQL_EscapeString(g_hDatabase, steamId, qSteamId, len);
	
	int maxRows = (max <= 0) ? ((g_iStatsMaxTopPlayers.IntValue <= 0) ? DEFAULT_MAX_TOP_PLAYERS : g_iStatsMaxTopPlayers.IntValue) : max;
	
	char query[512];
	FormatEx(query, sizeof(query), "select * from STATS_VW_PLAYER_RANKS s LIMIT %i", maxRows);
	
	Debug("Executing query: %s", query);
	
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(maxRows);
	
	g_hDatabase.Query(TQ_ShowTopPlayers, query, pack);
}

/**
* SQL Callback for Show Top Players Command
*/
public void TQ_ShowTopPlayers(Database db, DBResultSet results, const char[] error, any data) {
	DataPack pack = data;
	StringMap map = new StringMap();
	
	pack.Reset();
	int clientId = pack.ReadCell();
	int maxRows = pack.ReadCell();
	
	Debug("Displaying Total of %i entries", maxRows);
	
	char msg[255];
	Menu menu = new Menu(TopPlayerStatsMenuHandler);
	menu.ExitButton = true;
	
	FormatEx(msg, sizeof(msg), "Top %i Players", maxRows);
	menu.SetTitle(msg);
	
	while (ExtractPlayerStats(results, map)) {
		char steamId[128];
		char lastKnownAlias[255];
		int rankNum;
		
		map.GetString(STATS_STEAM_ID, steamId, sizeof(steamId));
		map.GetString(STATS_LAST_KNOWN_ALIAS, lastKnownAlias, sizeof(lastKnownAlias));
		map.GetValue(STATS_RANK, rankNum);
		
		Debug("> Player: %s", lastKnownAlias);
		Format(msg, sizeof(msg), "%s (Rank %d)", lastKnownAlias, rankNum);
		menu.AddItem(steamId, msg);
		
		delete map;
		map = new StringMap();
	}
	
	menu.Display(clientId, g_iStatsMenuTimeout.IntValue);
	
	delete pack;
	delete map;
}

public int TopPlayerStatsMenuHandler(Menu menu, MenuAction action, int clientId, int idIndex)
{
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select)
	{
		char steamId[64];
		bool found = menu.GetItem(idIndex, steamId, sizeof(steamId));
		
		if (found) {
			ShowPlayerRankPanel(clientId, steamId);
		}
	}
	/* If the menu was cancelled, print a message to the server about it. */
	else if (action == MenuAction_Cancel)
	{
		Debug("Client %N's menu was cancelled.  Reason: %d", clientId, idIndex);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

/**
* Method to display the rank/stats panel to the player
*/
public void ShowPlayerRankPanel(int client, const char[] steamId) {
	//Check if a request is already in progress
	if (g_bShowingRankPanel[client]) {
		if (IS_VALID_HUMAN(client)) {
			LogAction(client, -1, "Your request is already being processed");
			return;
		}
	}
	
	if (!IS_VALID_HUMAN(client)) {
		Debug("Skipping display of rank panel for client %i. Not a valid human player", client);
		return;
	}
	
	char clientSteamId[128];
	
	if (GetClientAuthId(client, AuthId_Steam2, clientSteamId, sizeof(clientSteamId)) && StrEqual(clientSteamId, steamId)) {
		Info("Player '%N' is viewing his own rank", client);
	} else {
		Info("Player '%N' is viewing the rank of steam id '%s'", client, steamId);
	}
	
	int len = strlen(steamId) * 2 + 1;
	char[] qSteamId = new char[len];
	SQL_EscapeString(g_hDatabase, steamId, qSteamId, len);
	
	char query[512];
	FormatEx(query, sizeof(query), "select * from STATS_VW_PLAYER_RANKS s WHERE s.steam_id = '%s'", qSteamId);
	
	g_bShowingRankPanel[client] = true;
	g_hDatabase.Query(TQ_ShowPlayerRankPanel, query, client);
}

/**
* SQL Callback for Player Rank/Stats Panel 
*/
public void TQ_ShowPlayerRankPanel(Database db, DBResultSet results, const char[] error, any data) {
	/* Make sure the client didn't disconnect while the thread was running */
	if (!IS_VALID_CLIENT(data)) {
		Debug("TQ_PlayerStatsMenu :: Client '%i' is not a valid client index, skipping display stats", data);
		g_bShowingRankPanel[data] = false;
		return;
	}
	
	if (results == null) {
		LogError("TQ_PlayerStatsMenu :: Query failed! %s", error);
		Debug("TQ_PlayerStatsMenu :: Query failed! %s", error);
		g_bShowingRankPanel[data] = false;
	} else if (results.RowCount > 0) {
		StringMap map = new StringMap();
		
		if (ExtractPlayerStats(results, map)) {
			char steamId[128];
			char lastKnownAlias[255];
			int createDate;
			int lastJoinDate;
			float totalPoints;
			int rankNum;
			int survivorsKilled;
			int survivorsIncapped;
			int infectedKilled;
			int infectedHeadshot;
			
			map.GetString(STATS_STEAM_ID, steamId, sizeof(steamId));
			map.GetString(STATS_LAST_KNOWN_ALIAS, lastKnownAlias, sizeof(lastKnownAlias));
			map.GetValue(STATS_LAST_JOIN_DATE, lastJoinDate);
			map.GetValue(STATS_TOTAL_POINTS, totalPoints);
			map.GetValue(STATS_RANK, rankNum);
			map.GetValue(STATS_SURVIVOR_KILLED, survivorsKilled);
			map.GetValue(STATS_SURVIVOR_INCAPPED, survivorsIncapped);
			map.GetValue(STATS_INFECTED_KILLED, infectedKilled);
			map.GetValue(STATS_INFECTED_HEADSHOT, infectedHeadshot);
			map.GetValue(STATS_CREATE_DATE, createDate);
			
			char msg[255];
			
			Panel panel = new Panel();
			if (!StringBlank(g_ConfigPanelTitle)) {
				panel.SetTitle(g_ConfigPanelTitle);
			}
			
			//♦ •
			panel.DrawText(" ");
			
			Format(msg, sizeof(msg), "Name: %s", lastKnownAlias);
			panel.DrawText(msg);
			
			Format(msg, sizeof(msg), "Rank: %i", rankNum);
			panel.DrawText(msg);
			Format(msg, sizeof(msg), "Points: %.2f", totalPoints);
			panel.DrawText(msg);
			panel.DrawText(" ");
			
			Format(msg, sizeof(msg), "Survivor (%i)", infectedKilled + infectedHeadshot);
			panel.DrawItem(msg, ITEMDRAW_DEFAULT);
			
			Format(msg, sizeof(msg), "☼ Kills: %i", infectedKilled);
			panel.DrawItem(msg, ITEMDRAW_RAWLINE);
			
			Format(msg, sizeof(msg), "☼ Headshots: %i", infectedHeadshot);
			panel.DrawItem(msg, ITEMDRAW_RAWLINE);
			panel.DrawText(" ");
			
			Format(msg, sizeof(msg), "Infected (%i)", survivorsKilled + survivorsIncapped);
			panel.DrawItem(msg, ITEMDRAW_DEFAULT);
			
			Format(msg, sizeof(msg), "☼ Kills: %i", survivorsKilled);
			panel.DrawItem(msg, ITEMDRAW_RAWLINE);
			
			Format(msg, sizeof(msg), "☼ Incaps: %i", survivorsIncapped);
			panel.DrawItem(msg, ITEMDRAW_RAWLINE);
			panel.DrawText(" ");
			
			panel.Send(data, PlayerStatsMenuHandler, g_iStatsMenuTimeout.IntValue);
		}
		
		delete map;
		g_bShowingRankPanel[data] = false;
	}
}

public int PlayerStatsMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select)
	{
		/*char info[32];
		bool found = menu.GetItem(param2, info, sizeof(info));
		PrintToConsole(param1, "You selected item: %d (found? %d info: %s)", param2, found, info);*/
	}
	/* If the menu was cancelled, print a message to the server about it. */
	else if (action == MenuAction_Cancel)
	{
		//Debug("Client %d's menu was cancelled.  Reason: %d", param1, param2);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

/**
* Helper function for extracting a single row of player statistic from the result set and store it on a map
* 
* @return true if the extraction was succesful from the result set, otherwise false if the extraction failed.
*/
public bool ExtractPlayerStats(DBResultSet & results, StringMap & map) {
	if (results == INVALID_HANDLE || map == INVALID_HANDLE)
		return false;
	
	if (results.FetchRow()) {
		int idxSteamId = -1;
		int idxLastKnownAlias = -1;
		int idxLastJoinDate = -1;
		int idxSurvivorsKilled = -1;
		int idxSurvivorsIncapped = -1;
		int idxInfectedKilled = -1;
		int idxInfectedHeadshot = -1;
		int idxTotalPoints = -1;
		int idxPlayerRank = -1;
		int idxCreateDate = -1;
		
		//Retrieve field indices
		results.FieldNameToNum(STATS_STEAM_ID, idxSteamId);
		results.FieldNameToNum(STATS_LAST_KNOWN_ALIAS, idxLastKnownAlias);
		results.FieldNameToNum(STATS_LAST_JOIN_DATE, idxLastJoinDate);
		results.FieldNameToNum(STATS_SURVIVOR_KILLED, idxSurvivorsKilled);
		results.FieldNameToNum(STATS_SURVIVOR_INCAPPED, idxSurvivorsIncapped);
		results.FieldNameToNum(STATS_INFECTED_KILLED, idxInfectedKilled);
		results.FieldNameToNum(STATS_INFECTED_HEADSHOT, idxInfectedHeadshot);
		results.FieldNameToNum(STATS_TOTAL_POINTS, idxTotalPoints);
		results.FieldNameToNum(STATS_RANK, idxPlayerRank);
		results.FieldNameToNum(STATS_CREATE_DATE, idxCreateDate);
		
		//Fetch values
		char steamId[128];
		char lastKnownAlias[255];
		int lastJoinDate = 0;
		float totalPoints = 0.0;
		int rankNum = -1;
		int survivorsKilled = 0;
		int survivorsIncapped = 0;
		int infectedKilled = 0;
		int infectedHeadshot = 0;
		int createDate = 0;
		
		results.FetchString(idxSteamId, steamId, sizeof(steamId));
		results.FetchString(idxLastKnownAlias, lastKnownAlias, sizeof(lastKnownAlias));
		lastJoinDate = results.FetchInt(idxLastJoinDate);
		createDate = results.FetchInt(idxCreateDate);
		totalPoints = results.FetchFloat(idxTotalPoints);
		rankNum = results.FetchInt(idxPlayerRank);
		survivorsKilled = results.FetchInt(idxSurvivorsKilled);
		survivorsIncapped = results.FetchInt(idxSurvivorsIncapped);
		infectedKilled = results.FetchInt(idxInfectedKilled);
		infectedHeadshot = results.FetchInt(idxInfectedHeadshot);
		createDate = results.FetchInt(idxCreateDate);
		
		map.SetString(STATS_STEAM_ID, steamId, true);
		map.SetString(STATS_LAST_KNOWN_ALIAS, lastKnownAlias, true);
		map.SetValue(STATS_LAST_JOIN_DATE, lastJoinDate, true);
		map.SetValue(STATS_TOTAL_POINTS, totalPoints, true);
		map.SetValue(STATS_RANK, rankNum, true);
		map.SetValue(STATS_SURVIVOR_KILLED, survivorsKilled, true);
		map.SetValue(STATS_SURVIVOR_INCAPPED, survivorsIncapped, true);
		map.SetValue(STATS_INFECTED_KILLED, infectedKilled, true);
		map.SetValue(STATS_INFECTED_HEADSHOT, infectedHeadshot, true);
		map.SetValue(STATS_CREATE_DATE, createDate, true);
		
		return true;
	}
	
	return false;
}

/**
* Returns the number of human players currently in the server
*/
public int GetHumanPlayerCount() {
	int count = 0;
	for (int i = 1; i <= MAX_CLIENTS; i++) {
		if (IS_VALID_HUMAN(i))
			count++;
	}
	return count;
}

/**
* Iterates and initialize all available players on the server
*/
public void InitializePlayers() {
	Debug("======================================");
	Debug("Initialize Players");
	Debug("======================================");
	
	for (int i = 1; i <= MAX_CLIENTS; i++)
	{
		if (IS_VALID_HUMAN(i))
		{
			if (IsClientConnected(i) && isInitialized(i)) {
				Debug("\tClient '%N' is already initialized. Skipping process.", i);
				continue;
			}
			Debug("\t%i) Initializing %N", i, i);
			InitializePlayer(i, false);
		}
	}
	
	Debug("======================================");
}

/**
* Initialize a player record if not yet existing
*
* @param client The client index to initialize
*/
public void InitializePlayer(int client, bool updateJoinDateIfExists) {
	if (!IS_VALID_CLIENT(client) || IsFakeClient(client)) {
		Debug("InitializePlayer :: Client %i (%N) is not valid. Skipping Initialization", client, client);
		return;
	}
	
	if (g_bInitializing[client]) {
		Debug("Initialization for '%N' is already in-progress. Please wait.");
		return;
	}
	
	char steamId[255];
	GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId));
	
	char name[255];
	GetClientName(client, name, sizeof(name));
	
	int len = strlen(steamId) * 2 + 1;
	char[] qSteamId = new char[len];
	SQL_EscapeString(g_hDatabase, steamId, qSteamId, len);
	
	len = strlen(name) * 2 + 1;
	char[] qName = new char[len];
	SQL_EscapeString(g_hDatabase, name, qName, len);
	
	char query[512];
	
	if (updateJoinDateIfExists) {
		Debug("InitializePlayer :: Join date will be updated for %N", client);
		FormatEx(query, sizeof(query), "INSERT INTO STATS_PLAYERS (steam_id, last_known_alias, last_join_date, survivor_killed, survivor_incapped, infected_killed, infected_headshot) VALUES ('%s', '%s', CURRENT_TIMESTAMP(), 0, 0, 0, 0) ON DUPLICATE KEY UPDATE last_join_date = CURRENT_TIMESTAMP(), last_known_alias = '%s'", qSteamId, qName, qName);
	}
	else {
		Debug("InitializePlayer :: Join date will NOT be updated for %N", client);
		FormatEx(query, sizeof(query), "INSERT INTO STATS_PLAYERS (steam_id, last_known_alias, last_join_date, survivor_killed, survivor_incapped, infected_killed, infected_headshot) VALUES ('%s', '%s', CURRENT_TIMESTAMP(), 0, 0, 0, 0) ON DUPLICATE KEY UPDATE last_known_alias = '%s'", qSteamId, qName, qName);
	}
	
	g_bInitializing[client] = true;
	g_hDatabase.Query(TQ_InitializePlayer, query, client);
}

/**
* SQL Callback for InitializePlayer threaded query
*/
public void TQ_InitializePlayer(Database db, DBResultSet results, const char[] error, any data) {
	int client = data;
	
	if (!IS_VALID_CLIENT(client)) {
		Debug("TQ_InitializePlayer :: Client %N (%i) is not valid. Skipping initialization", client, client);
		g_bInitializing[client] = false;
		return;
	}
	
	if (results == null) {
		LogError("TQ_InitializePlayer :: Query failed (Reason: %s)", error);
		Debug("TQ_InitializePlayer :: Query failed  (Reason: %s)", error);
		g_bPlayerInitialized[client] = false;
		g_bInitializing[client] = false;
		return;
	}
	
	if (results.AffectedRows == 0) {
		Debug("TQ_InitializePlayer :: Nothing was updated for player %N", client);
	}
	else if (results.AffectedRows == 1) {
		Debug("TQ_InitializePlayer :: Player %N has been initialized for the first time", client);
	}
	else if (results.AffectedRows > 1) {
		Debug("TQ_InitializePlayer :: Existing record has been updated for player %N", client);
	}
	
	g_bPlayerInitialized[client] = true;
	g_bInitializing[client] = false;
}

/**
* Connect to the database
* 
* @return true if the connection is successful
*/
public bool DbConnect()
{
	if (g_hDatabase != INVALID_HANDLE) {
		return true;
	}
	if (SQL_CheckConfig(DB_CONFIG_NAME)) {
		char error[512];
		g_hDatabase = SQL_Connect(DB_CONFIG_NAME, true, error, sizeof(error));
		if (g_hDatabase != INVALID_HANDLE) {
			LogMessage("Connected to the database: %s", DB_CONFIG_NAME);
			return true;
		} else {
			LogError("Failed to connect to database: %s", error);
		}
	}
	return false;
}

/**
* Initialize database (create tables/indices etc)
*
* @return true if the initialization is successfull
*/
public bool InitDatabase() {
	if (!DbConnect()) {
		LogError("Unable to retrieve database handle");
		return false;
	}
	return true;
}

/**
* Method to trigger the Player Connect Announcement in Chat
*/
public void PlayerConnectAnnounce(int client) {
	if (!IS_VALID_CLIENT(client) || IsFakeClient(client) || !IsClientAuthorized(client)) {
		Debug("PlayerConnectAnnounce() :: Skipping connect announce for %N)", client);
		return;
	}
	
	char steamId[128];
	GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId));
	
	int len = strlen(steamId) * 2 + 1;
	char[] qSteamId = new char[len];
	SQL_EscapeString(g_hDatabase, steamId, qSteamId, len);
	
	char query[512];
	FormatEx(query, sizeof(query), "select * from STATS_VW_PLAYER_RANKS s WHERE s.steam_id = '%s'", qSteamId);
	
	Debug("Executing Query: %s", query);
	
	g_hDatabase.Query(TQ_PlayerConnectAnnounce, query, client);
}

/**
* SQL callback for the Player Connect Announcement
*/
public void TQ_PlayerConnectAnnounce(Database db, DBResultSet results, const char[] error, any data) {
	
	/* Make sure the client didn't disconnect while the thread was running */
	if (!IS_VALID_CLIENT(data)) {
		Debug("Client '%i' is not a valid client index, skipping display stats", data);
		return;
	}
	
	if (results == null) {
		LogError("TQ_PrintPlayerStatsChat :: Query failed! %s", error);
		Debug("TQ_PrintPlayerStatsChat :: Query failed! %s", error);
	} else if (results.RowCount > 0) {
		
		StringMap map = new StringMap();
		
		if (ExtractPlayerStats(results, map)) {
			char steamId[128];
			char lastKnownAlias[255];
			int createDate;
			int lastJoinDate;
			float totalPoints;
			int rankNum;
			int survivorsKilled;
			int survivorsIncapped;
			int infectedKilled;
			int infectedHeadshot;
			
			map.GetString(STATS_STEAM_ID, steamId, sizeof(steamId));
			map.GetString(STATS_LAST_KNOWN_ALIAS, lastKnownAlias, sizeof(lastKnownAlias));
			map.GetValue(STATS_LAST_JOIN_DATE, lastJoinDate);
			map.GetValue(STATS_TOTAL_POINTS, totalPoints);
			map.GetValue(STATS_RANK, rankNum);
			map.GetValue(STATS_SURVIVOR_KILLED, survivorsKilled);
			map.GetValue(STATS_SURVIVOR_INCAPPED, survivorsIncapped);
			map.GetValue(STATS_INFECTED_KILLED, infectedKilled);
			map.GetValue(STATS_INFECTED_HEADSHOT, infectedHeadshot);
			map.GetValue(STATS_CREATE_DATE, createDate);
			
			char tmpMsg[253];
			
			//parse stats
			ParseStatsKeywords(g_ConfigAnnounceFormat, tmpMsg, sizeof(tmpMsg), map);
			Debug("PARSE RESULT = %s", tmpMsg);
			
			Client_PrintToChatAll(true, tmpMsg);
			
			Debug("'%N' has joined the game (Id: %s, Points: %f, Rank: %i, Last Known Alias: %s)", data, steamId, totalPoints, rankNum, lastKnownAlias);
		}
		
		delete map;
	}
}

/**
* Parse player stats keywords within the text and replace with values associated with the player
* 
* @param text The text to parse
* @param buffer The buffer to store the output
* @param size The size of the output buffer
* @param map The StringMap containing the key/value pairs that will be used for lookup
*/
public void ParseStatsKeywords(const char[] text, char[] buffer, int size, StringMap & map) {
	Debug("Parsing stats string : \"%s\"", text);
	
	StringMapSnapshot keys = map.Snapshot();
	
	//Copy content
	FormatEx(buffer, size, "%s", g_ConfigAnnounceFormat);
	
	//iterate through all available keys in the map
	for (int i = 0; i < keys.Length; i++) {
		int bufferSize = keys.KeyBufferSize(i);
		char[] keyName = new char[bufferSize];
		keys.GetKey(i, keyName, bufferSize);
		
		int searchKeySize = bufferSize + 32;
		
		//Standard search key
		char[] searchKey = new char[searchKeySize];
		FormatEx(searchKey, searchKeySize, "{%s}", keyName);
		
		char[] searchKeyFloat = new char[searchKeySize];
		FormatEx(searchKeyFloat, searchKeySize, "{f:%s}", keyName);
		
		char[] searchKeyInt = new char[searchKeySize];
		FormatEx(searchKeyInt, searchKeySize, "{i:%s}", keyName);
		
		char[] searchKeyDate = new char[searchKeySize];
		FormatEx(searchKeyDate, searchKeySize, "{d:%s}", keyName);
		
		char[] sKey = new char[searchKeySize];
		
		int pos = -1;
		
		char valueStr[128];
		
		bool found = false;
		
		//If we find the key, then replace it with the actual value
		if ((pos = StrContains(g_ConfigAnnounceFormat, searchKey, false)) > -1) {
			//Try extract string		
			map.GetString(keyName, valueStr, sizeof(valueStr));
			
			//If string value is empty, try int
			/*if (StringBlank(valueStr)) {
				int valueInt;
				map.GetValue(keyName, valueInt);
				if (valueInt >= 0) {
					IntToString(valueInt, valueStr, sizeof(valueStr));
				} else {
					Format(valueStr, sizeof(valueStr), "N/A");
				}
			}*/
			Debug("(%i: %s) Key '%s' FOUND at position %i in (value = %s, type = string)", i, keyName, searchKey, pos, valueStr);
			FormatEx(sKey, searchKeySize, searchKey);
			found = true;
		} else if ((pos = StrContains(g_ConfigAnnounceFormat, searchKeyFloat, false)) > -1) {
			float valueFloat;
			map.GetValue(keyName, valueFloat);
			FormatEx(valueStr, sizeof(valueStr), "%.2f", valueFloat);
			FormatEx(sKey, searchKeySize, searchKeyFloat);
			Debug("(%i: %s) Key '%s' FOUND at position %i in (value = %s, type = float)", i, keyName, sKey, pos, valueStr);
			found = true;
		} else if ((pos = StrContains(g_ConfigAnnounceFormat, searchKeyInt, false)) > -1) {
			int valueInt;
			map.GetValue(keyName, valueInt);
			FormatEx(valueStr, sizeof(valueStr), "%i", valueInt);
			FormatEx(sKey, searchKeySize, searchKeyInt);
			Debug("(%i: %s) Key '%s' FOUND at position %i in (value = %s, type = integer)", i, keyName, sKey, pos, valueStr);
			found = true;
		}
		else {
			Debug("(%i: %s) Key '%s' NOT FOUND in '%s'", i, keyName, searchKey, g_ConfigAnnounceFormat);
			Format(valueStr, sizeof(valueStr), "N/A");
		}
		
		if (!found) {
			Debug("Key not found: '%s'. Skipping replacement", keyName);
			continue;
		}
		//Perform the replacement
		Debug("Replacing key '%s' with value '%s'", sKey, valueStr);
		ReplaceString(buffer, size, sKey, valueStr, false);
	}
}

stock bool StringBlank(const char[] text) {
	int len = strlen(text);
	char[] tmp = new char[len];
	String_Trim(text, tmp, len);
	return StrEqual(tmp, "");
}

public Action Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast) {
	Debug("================================== OnRoundStart ==================================");
	return Plugin_Continue;
}

public Action Event_OnRoundEnd(Event event, const char[] name, bool dontBroadcast) {
	Debug("================================== OnRoundEnd ==================================");
	return Plugin_Continue;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	return Plugin_Continue;
}

public Action Event_PlayerIncapped(Event event, const char[] name, bool dontBroadcast) {
	int victimId = event.GetInt("userid");
	int attackerId = event.GetInt("attacker");
	int attackerClientId = GetClientOfUserId(attackerId);
	int victimClientId = GetClientOfUserId(victimId);
	
	if (IS_VALID_CLIENT(attackerClientId) && !IsFakeClient(attackerClientId)) {
		if (IS_VALID_INFECTED(attackerClientId) && IS_VALID_SURVIVOR(victimClientId)) {
			UpdateStat(attackerClientId, STATS_SURVIVOR_INCAPPED, 1);
		} else {
			Debug("Skipped stats update for attacker %N", attackerClientId);
		}
	}
	
	return Plugin_Continue;
}

public Action Event_WitchKilled(Event event, const char[] name, bool dontBroadcast) {
	int attackerId = event.GetInt("userid");
	int attackerClientId = GetClientOfUserId(attackerId);
	int witchId = event.GetInt("witchid");
	bool oneShot = event.GetBool("oneshot");
	
	//We will only process valid human survivor players
	if (!IS_VALID_HUMAN(attackerClientId) || !IS_VALID_SURVIVOR(attackerClientId))
		return Plugin_Continue;
	
	if (!AllowCollectStats()) {
		Debug("Stats collection is curerntly disabled. Skipping for client %N", attackerClientId);
		return Plugin_Continue;
	}
	
	char entityClassName[64];
	Entity_GetClassName(witchId, entityClassName, sizeof(entityClassName));
	
	if (oneShot) {
		PrintToChatAll("%N has crowned the witch. Fuck Yea!", attackerClientId);
	} else {
		PrintToChatAll("%N has killed the witch..Try crowning next time?", attackerClientId);
	}
	
	UpdateStat(attackerClientId, STATS_INFECTED_KILLED, 1);
	
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victimId = event.GetInt("userid");
	int attackerId = event.GetInt("attacker");
	int attackerClientId = GetClientOfUserId(attackerId);
	int victimClientId = GetClientOfUserId(victimId);
	//int entityId = event.GetInt("entityid");
	bool headshot = event.GetBool("headshot");
	bool attackerIsBot = event.GetBool("attackerisbot");
	bool victimIsBot = event.GetBool("victimisbot");
	
	if (IS_VALID_CLIENT(attackerClientId) && !attackerIsBot) {
		if (!AllowCollectStats()) {
			Debug("Stats collection is curerntly disabled. Skipping for client %N", attackerClientId);
			return Plugin_Continue;
		}
		
		if (g_bRecordBots.IntValue <= 0 && victimIsBot) {
			Debug("Skipping stat update for attacker %N. Victim '%N' is a bot", attackerClientId, victimClientId);
			return Plugin_Continue;
		}
		
		char steamId[64];
		GetClientAuthId(attackerClientId, AuthId_Steam2, steamId, sizeof(steamId));
		
		//survivor killed infected
		if (IS_VALID_SURVIVOR(attackerClientId) && IS_VALID_INFECTED(victimClientId)) {
			if (headshot) {
				UpdateStat(attackerClientId, STATS_INFECTED_HEADSHOT, 1);
			}
			UpdateStat(attackerClientId, STATS_INFECTED_KILLED, 1);
		}
		//infected killed survivor
		else if (IS_VALID_INFECTED(attackerClientId) && IS_VALID_SURVIVOR(victimClientId)) {
			UpdateStat(attackerClientId, STATS_SURVIVOR_KILLED, 1);
		} else {
			//Debug("Skipped stats update for attacker %N", attackerClientId);
		}
	}
	return Plugin_Continue;
}

/**
* Utility function for updating the stat field of the player
*/
public void UpdateStat(int client, const char[] column, int amount) {
	if (!IS_VALID_HUMAN(client)) {
		PrintToChatAll("Skipping update stat. Client is not valid: %N", client);
		return;
	}
	
	if (!isInitialized(client)) {
		PrintToChatAll("Skipping update stat. Client is not initialized %N", client);
		return;
	}
	
	if (!AllowCollectStats()) {
		Debug("Stats collection is curerntly disabled. Skipping for client %N", client);
		return;
	}
	
	char steamId[255];
	GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId));
	
	char name[255];
	GetClientName(client, name, sizeof(name));
	
	int len = strlen(steamId) * 2 + 1;
	char[] qSteamId = new char[len];
	SQL_EscapeString(g_hDatabase, steamId, qSteamId, len);
	
	len = strlen(column) * 2 + 1;
	char[] qColumnName = new char[len];
	SQL_EscapeString(g_hDatabase, column, qColumnName, len);
	
	len = strlen(name) * 2 + 1;
	char[] qName = new char[len];
	SQL_EscapeString(g_hDatabase, name, qName, len);
	
	/*loat modifier;
	if (!g_mStatModifiers.GetValue(column, modifier)) {
		LogError("No modifier found for key '%s'. Using default value of 1.0", column);
		modifier = 1.0;
	}*/
	
	char query[255];
	FormatEx(query, sizeof(query), "UPDATE STATS_PLAYERS SET %s = %s + %i, last_known_alias = '%s' WHERE steam_id = '%s'", qColumnName, qColumnName, amount, qName, qSteamId);
	g_hDatabase.Query(TQ_UpdateStat, query, client);
}

public void TQ_UpdateStat(Database db, DBResultSet results, const char[] error, any data) {
	if (results == null) {
		LogError("Query failed! %s", error);
		return;
	}
	
	if (results.AffectedRows > 0) {
		Debug("Stat successfully updated for %N", data);
	}
	else {
		Debug("Stat not updated for %N", data);
	}
}

public void PrintStats(const char[] desc, Event event) {
	int victimId = event.GetInt("userid");
	int attackerId = event.GetInt("attacker");
	int entityId = event.GetInt("entityid");
	bool headshot = event.GetBool("headshot");
	int type = event.GetInt("type");
	
	char attackerName[64];
	char victimName[64];
	char weapon[64];
	char entityClassName[64];
	
	int attackerClientId = GetClientOfUserId(attackerId);
	int victimClientId = GetClientOfUserId(victimId);
	
	event.GetString("weapon", weapon, sizeof(weapon));
	
	if (IS_VALID_CLIENT(attackerClientId)) {
		Format(attackerName, sizeof(attackerName), "%N", attackerClientId);
	} else {
		Format(attackerName, sizeof(attackerName), "N/A");
	}
	
	if (IS_VALID_CLIENT(victimClientId)) {
		Format(victimName, sizeof(victimName), "%N", victimClientId);
	} else {
		Entity_GetClassName(entityId, entityClassName, sizeof(entityClassName));
		Format(victimName, sizeof(victimName), "N/A = (Entity: %s)", entityClassName);
	}
	
	if (headshot) {
		Debug("%s :: '%s' has HEADSHOT killed '%s' with a '%s' (Damage Type: %i)", desc, attackerName, victimName, weapon, type);
		return;
	}
	
	Debug("%s :: '%s' has killed '%s' with a '%s' (Damage Type: %i)", desc, attackerName, victimName, weapon, type);
}

public void PrintSqlVersion() {
	DBResultSet tmpQuery = SQL_Query(g_hDatabase, "select VERSION()");
	if (tmpQuery == null)
	{
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		Debug("Failed to query (error: %s)", error);
	}
	else
	{
		if (SQL_FetchRow(tmpQuery)) {
			char version[255];
			SQL_FetchString(tmpQuery, 0, version, sizeof(version));
			Debug("SQL DB VERSION: %s", version);
		}
		/* Free the Handle */
		delete tmpQuery;
	}
}

public void Error(const char[] format, any...)
{
	int len = strlen(format) + 255;
	char[] formattedString = new char[len];
	VFormat(formattedString, len, format, 2);
	
	len = len + 8;
	char[] debugMessage = new char[len];
	Format(debugMessage, len, "[ERROR] %s", formattedString);
	
	PrintToServer(debugMessage);
	LogError(debugMessage);
	
	//Display debug messages to root admins
	for (int i = 1; i <= MAX_CLIENTS; i++) {
		if (IS_VALID_HUMAN(i) && Client_IsAdmin(i) && Client_HasAdminFlags(i, ADMFLAG_ROOT))
			PrintToConsole(i, debugMessage);
	}
}

/**
*
*/
public void Info(const char[] format, any...)
{
	int len = strlen(format) + 255;
	char[] formattedString = new char[len];
	VFormat(formattedString, len, format, 2);
	
	len = len + 8;
	char[] debugMessage = new char[len];
	Format(debugMessage, len, "[INFO] %s", formattedString);
	
	PrintToServer(debugMessage);
	LogMessage(debugMessage);
	
	//Display debug messages to root admins
	for (int i = 1; i <= MAX_CLIENTS; i++) {
		if (IS_VALID_HUMAN(i) && Client_IsAdmin(i) && Client_HasAdminFlags(i, ADMFLAG_ROOT))
			PrintToConsole(i, debugMessage);
	}
}

/**
* Used for printing debug information to the server and client console. This does not display messages when debug mode is disabled.
*/
public void Debug(const char[] format, any...)
{
	if (g_bDebug == null || g_bDebug.IntValue <= 0) {
		return;
	}
	
	int len = strlen(format) + 255;
	char[] formattedString = new char[len];
	VFormat(formattedString, len, format, 2);
	
	len = len + 8;
	char[] debugMessage = new char[len];
	Format(debugMessage, len, "[DEBUG] %s", formattedString);
	
	PrintToServer(debugMessage);
	LogMessage(debugMessage);
	
	//Display debug messages to root admins
	for (int i = 1; i <= MAX_CLIENTS; i++) {
		if (IS_VALID_HUMAN(i) && Client_IsAdmin(i) && Client_HasAdminFlags(i, ADMFLAG_ROOT))
			PrintToConsole(i, debugMessage);
	}
} 