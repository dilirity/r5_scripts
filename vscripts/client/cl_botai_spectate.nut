untyped

global function ClBotAI_Spectate_Init
global function ServerCallback_BotSpectate_Start
global function ServerCallback_BotSpectate_Stop

struct {
	entity camera = null
	entity vguiScreen = null
	PIPSlotState ornull pipSlotState = null
	entity trackedBot = null
	bool   isActive = false
} file

// ============================================================================
// Init
// ============================================================================

void function ClBotAI_Spectate_Init()
{
	RegisterSignal( "BotSpectate_Stop" )
}

// ============================================================================
// Start / Stop callbacks (called by server via Remote_CallFunction_NonReplay)
// ============================================================================

void function ServerCallback_BotSpectate_Start( int botEntIndex )
{
	// Tear down existing spectate if active
	if ( file.isActive )
		BotSpectate_Cleanup()

	entity bot = GetEntByIndex( botEntIndex )
	if ( !IsValid( bot ) )
	{
		printt( "[BotSpectate] Invalid entity index:", botEntIndex )
		return
	}

	entity player = GetLocalViewPlayer()
	if ( !IsValid( player ) )
		return

	entity cockpit = player.GetCockpit()
	if ( !IsValid( cockpit ) )
	{
		printt( "[BotSpectate] No cockpit available — cannot create HUD display" )
		return
	}

	// Create camera at bot's current eye position
	entity camera = CreateClientSidePointCamera( bot.EyePosition(), bot.EyeAngles(), 90.0 )
	camera.SetMonitorZFar( 100000 )
	camera.SetMonitorExposure( 2 )

	// Assign camera to a PIP monitor slot
	PIPSlotState pipSlotState = BeginMovingPIP( camera, -1 )
	int slotIndex = PIPSlotState_GetSlotID( pipSlotState )

	// Create cockpit-space VGUI screen (same pattern as Create_Hud in cl_main_hud.nut)
	// Position: center-right of the screen
	float pipSize = 14.0   // world units — square panel to match square PIP render target

	vector origin = <0, 0, 0>
	vector angles = <0, 0, 0>

	// Forward: same distance as main HUD
	origin += AnglesToForward( angles ) * COCKPIT_UI_XOFFSET

	// Right: right edge of screen with small margin
	float margin = 0.5
	origin += AnglesToRight( angles ) * (COCKPIT_UI_WIDTH / 2 - pipSize - margin)

	// Up: centered vertically
	origin += AnglesToUp( angles ) * (-pipSize / 2)

	angles = AnglesCompose( angles, <0, -90, 90> )

	entity vgui = CreateClientsideVGuiScreen( "botai_spectate", VGUI_SCREEN_PASS_COCKPIT, origin, angles, pipSize, pipSize )
	vgui.s.panel <- vgui.GetPanel()

	vgui.SetParent( cockpit, "CAMERA_BASE" )
	vgui.SetAttachOffsetOrigin( origin )
	vgui.SetAttachOffsetAngles( angles )

	// Connect PIP render target to the VGUI panel
	Hud_SetImage( HudElement( "BotSpectateCam", vgui.s.panel ), CastStringToAsset( "vgui/hud/vdu_hud_cam" + slotIndex ) )

	// Store state
	file.camera = camera
	file.vguiScreen = vgui
	file.pipSlotState = pipSlotState
	file.trackedBot = bot
	file.isActive = true

	printt( "[BotSpectate] Started spectating entity", botEntIndex, "on PIP slot", slotIndex )

	thread BotSpectate_ThinkThread( bot, camera )
}

void function ServerCallback_BotSpectate_Stop()
{
	BotSpectate_Cleanup()
}

// ============================================================================
// Think thread — updates camera to bot's eye position each frame
// ============================================================================

void function BotSpectate_ThinkThread( entity bot, entity camera )
{
	bot.EndSignal( "OnDestroy" )
	camera.EndSignal( "OnDestroy" )

	// Kill any previous think thread
	entity levelEnt = GetLocalViewPlayer()
	Signal( levelEnt, "BotSpectate_Stop" )
	levelEnt.EndSignal( "BotSpectate_Stop" )

	OnThreadEnd( function() {
		BotSpectate_Cleanup()
	})

	while ( file.isActive )
	{
		vector eyePos = bot.EyePosition()
		vector eyeAng = bot.EyeAngles()
		// Offset forward to avoid rendering the bot's own body
		vector forward = AnglesToForward( eyeAng )
		camera.SetOrigin( eyePos + forward * 10.0 )
		camera.SetAngles( eyeAng )
		WaitFrame()
	}
}

// ============================================================================
// Cleanup
// ============================================================================

void function BotSpectate_Cleanup()
{
	if ( !file.isActive )
		return

	file.isActive = false

	if ( file.pipSlotState != null )
	{
		ReleasePIP( expect PIPSlotState( file.pipSlotState ) )
		file.pipSlotState = null
	}

	if ( IsValid( file.camera ) )
		file.camera.Destroy()

	if ( IsValid( file.vguiScreen ) )
		file.vguiScreen.Destroy()

	file.camera = null
	file.vguiScreen = null
	file.trackedBot = null

	printt( "[BotSpectate] Stopped spectating" )
}
