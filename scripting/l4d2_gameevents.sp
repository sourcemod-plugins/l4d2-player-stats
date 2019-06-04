#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "mac & cheese (a.k.a thresh0ld)"
#define PLUGIN_VERSION "1.0.0"

#include <sourcemod>
#include <sdktools>
#include <smlib>

#pragma newdecls required

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
#define IS_HUMAN_SURVIVOR(%1)   (IS_VALID_HUMAN(%1) && IS_SURVIVOR(%1))
#define IS_HUMAN_INFECTED(%1)   (IS_VALID_HUMAN(%1) && IS_INFECTED(%1))

bool g_bGameStarted = false;
int g_iMatchStartTime = 0;

Handle g_hMatchStart;
Handle g_hMatchEnd;

public Plugin myinfo = 
{
	name = "Game Events", 
	author = PLUGIN_AUTHOR, 
	description = "A plugin which monitors certain useful event", 
	version = PLUGIN_VERSION, 
	url = ""
};

public void OnPluginStart() {
	g_hMatchStart = CreateGlobalForward("OnMatchStart", ET_Event, Param_String);
	g_hMatchEnd = CreateGlobalForward("OnMatchEnd", ET_Event, Param_Cell, Param_Cell);
	
	HookEvent("player_connect", Event_PlayerConnect, EventHookMode_Post);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);	
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max) {
	RegPluginLibrary("game_events");
}

public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) {
	Action result;
	char playerName[MAX_NAME_LENGTH];
	char steamId[MAX_STEAMAUTH_LENGTH];
	char ipAddress[16];
	
	event.GetString("name", playerName, sizeof(playerName));
	event.GetString("networkid", steamId, sizeof(steamId));
	event.GetString("address", ipAddress, sizeof(ipAddress));
	//int slot = event.GetInt("index");
	//int userid = event.GetInt("userid");
	bool isBot = event.GetBool("bot");
	
	if (!isBot) {
		if (!g_bGameStarted) {
			char mapName[MAX_NAME_LENGTH];
			g_bGameStarted = true;
			g_iMatchStartTime = GetTime();
			GetCurrentMap(mapName, sizeof(mapName));
			/* Start function call */
			Call_StartForward(g_hMatchStart);
			/* Push parameters one at a time */
			Call_PushString(mapName);
			/* Finish the call, get the result */
			Call_Finish(result);
			Debug("Forward Called: OnMatchStart");
		}
	}
	return result;
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	Action result;
	//char reason[512];
	//char playerName[MAX_NAME_LENGTH];
	//char networkId[255];
	
	int userId = event.GetInt("userid");
	int clientId = GetClientOfUserId(userId);
	
	/*event.GetString("name", playerName, sizeof(playerName));
	event.GetString("reason", reason, sizeof(reason));
	event.GetString("networkid", networkId, sizeof(networkId));
	int isBot = event.GetInt("bot");*/
	
	if (g_bGameStarted && GetHumanPlayerCount(true, clientId) == 0) {
		//Debug("\n\n\n\nGAME OFFICIALLY ENDED\n\n\n\n");
		char mapName[MAX_NAME_LENGTH];
		GetCurrentMap(mapName, sizeof(mapName));
		g_bGameStarted = false;
		/* Start function call */
		Call_StartForward(g_hMatchEnd);
		/* Push parameters one at a time */
		Call_PushString(mapName);
		Call_PushCell(GetTime() - g_iMatchStartTime);
		/* Finish the call, get the result */
		Call_Finish(result);
		Debug("Forward Called: OnMatchEnd");
	}
	return result;
}

/**
* Returns the number of human players currently in the server (including spectators)
*/
int GetHumanPlayerCount(bool includeSpec = true, int excludeClient = -1) {
	int count = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (excludeClient >= 1 && i == excludeClient)
			continue;
		if (includeSpec) {
			if (IS_VALID_HUMAN(i))
				count++;
		} else {
			if (IS_VALID_HUMAN(i) && (IS_VALID_SURVIVOR(i) || IS_VALID_INFECTED(i)))
				count++;
		}
	}
	return count;
}

/**
* Print and log plugin debug messages. This does not display messages when debug mode is disabled.
*/
public void Debug(const char[] format, any...)
{
	#if defined DEBUG
	
	int len = strlen(format) + 255;
	char[] formattedString = new char[len];
	VFormat(formattedString, len, format, 2);
	
	len = len + 8;
	char[] debugMessage = new char[len];
	Format(debugMessage, len, "[DEBUG] %s", formattedString);
	
	PrintToServer(debugMessage);
	LogMessage(debugMessage);
	
	//Display debug messages to root admins
	for (int i = 1; i <= MaxClients; i++) {
		if (IS_VALID_HUMAN(i) && Client_IsAdmin(i) && Client_HasAdminFlags(i, ADMFLAG_ROOT))
			PrintToConsole(i, debugMessage);
	}
	#endif
} 