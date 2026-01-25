extends Node
## System templates for remote computer simulations

# System categories
const CATEGORY_MAINFRAME = "mainframe"
const CATEGORY_MINI = "minicomputer"
const CATEGORY_BBS = "bbs"
const CATEGORY_UTILITY = "utility"
const CATEGORY_DEAD = "dead"
const CATEGORY_AI = "ai"

# All system templates
const SYSTEMS = [
	# ============================================================
	# VAX/VMS SYSTEMS
	# ============================================================
	{
		"id": "vms_school",
		"category": CATEGORY_MAINFRAME,
		"os": "VAX/VMS",
		"banner": """

        ╔══════════════════════════════════════════╗
        ║   JEFFERSON COUNTY SCHOOL DISTRICT #4    ║
        ║        Administrative Computing          ║
        ╚══════════════════════════════════════════╝

         VAX/VMS V4.7  Node: JCSD4

""",
		"prompt": "Username: ",
		"password_prompt": "Password: ",
		"login_response": "\n%LOGIN-F-INVPWD, invalid password\n\n",
		"max_attempts": 3,
		"lockout_msg": "\n%LOGIN-F-LKDOUT, account permanently locked\nConnection closed by remote host.\n"
	},
	{
		"id": "vms_research",
		"category": CATEGORY_MAINFRAME,
		"os": "VAX/VMS",
		"banner": """

    *****************************************
    *    WESTERN GEOLOGICAL SURVEY          *
    *    Research Computing Facility        *
    *    Unauthorized access prohibited     *
    *****************************************

    VAX 8600 runnnig VMS V5.2

""",
		"prompt": "Username: ",
		"password_prompt": "Password: ",
		"login_response": "\n%LOGIN-F-INVPWD, invalid password\n\n",
		"max_attempts": 3,
		"lockout_msg": "\n%LOGIN-F-LKDOUT, too many failures\n"
	},
	{
		"id": "vms_hospital",
		"category": CATEGORY_MAINFRAME,
		"os": "VAX/VMS",
		"banner": """

    ================================================
       ST. FRANCIS MEDICAL CENTER
       Patient Records System - Terminal 14
       
       WARNING: Contains confidential medical data
       Unauthorized access is a federal crime
    ================================================

    VAX/VMS V4.5

""",
		"prompt": "Username: ",
		"password_prompt": "Password: ",
		"login_response": "\n%LOGIN-F-INVPWD, invalid password\n\n",
		"max_attempts": 2,
		"lockout_msg": "\nSECURITY ALERT - Connection terminated\n"
	},
	
	# ============================================================
	# UNIX SYSTEMS
	# ============================================================
	{
		"id": "unix_university",
		"category": CATEGORY_MAINFRAME,
		"os": "UNIX",
		"banner": """

    UC Berkeley
    Computer Science Division
    
    4.2BSD UNIX (ucbvax)
    
""",
		"prompt": "login: ",
		"password_prompt": "Password:",
		"login_response": "\nLogin incorrect\n",
		"max_attempts": 3,
		"lockout_msg": ""
	},
	{
		"id": "unix_isp",
		"category": CATEGORY_MAINFRAME,
		"os": "UNIX",
		"banner": """
    
    =============================================
    PACIFIC DATANET - Regional Access Node 7
    System V Release 2.0
    =============================================
    
""",
		"prompt": "login: ",
		"password_prompt": "Password:",
		"login_response": "\nLogin incorrect\n",
		"max_attempts": 5,
		"lockout_msg": ""
	},
	{
		"id": "unix_corporate",
		"category": CATEGORY_MAINFRAME,
		"os": "UNIX",
		"banner": """

    AMALGAMATED INDUSTRIES INC.
    Corporate Data Processing
    SCO XENIX System V
    
    ** All access is logged and monitored **
    
""",
		"prompt": "login: ",
		"password_prompt": "Password:",
		"login_response": "\nLogin incorrect\n",
		"max_attempts": 3,
		"lockout_msg": "\nToo many login failures. Goodbye.\n"
	},
	
	# ============================================================
	# RSTS/E SYSTEMS
	# ============================================================
	{
		"id": "rsts_college",
		"category": CATEGORY_MAINFRAME,
		"os": "RSTS/E",
		"banner": """

RSTS/E V9.0-14  MIDLAND COMMUNITY COLLEGE

Job 23  KB34:  30-Mar-87  10:42 PM

""",
		"prompt": "User: ",
		"password_prompt": "Password: ",
		"login_response": "\n?Invalid entry - Loss 1\n\n",
		"max_attempts": 3,
		"lockout_msg": "\n?Too many invalid attempts\nHung up\n"
	},
	{
		"id": "rsts_business",
		"category": CATEGORY_MAINFRAME,
		"os": "RSTS/E",
		"banner": """

+------------------------------------------+
|     MARTIN & ASSOCIATES ACCOUNTING       |
|        Client Services Terminal          |
+------------------------------------------+

RSTS/E V8.0   Node: MARTIN

""",
		"prompt": "Account: ",
		"password_prompt": "Password: ",
		"login_response": "\n?Invalid account or password\n\n",
		"max_attempts": 3,
		"lockout_msg": "\n?Locked out\n"
	},
	
	# ============================================================
	# IBM SYSTEMS
	# ============================================================
	{
		"id": "ibm_tso",
		"category": CATEGORY_MAINFRAME,
		"os": "MVS/TSO",
		"banner": """
    
    **********************************************
    *                                            *
    *     FIRST NATIONAL BANK OF COMMERCE        *
    *     Data Processing Center                 *
    *     MVS/SP 1.3.5                          *
    *                                            *
    *   Unauthorized access strictly forbidden   *
    *                                            *
    **********************************************

    IKJ56700A ENTER USERID -
""",
		"prompt": "",
		"password_prompt": "IKJ56700A ENTER PASSWORD -\n",
		"login_response": "\nIKJ56421I PASSWORD NOT AUTHORIZED FOR USERID\n\nIKJ56700A ENTER USERID -\n",
		"max_attempts": 3,
		"lockout_msg": "\nIKJ56425I USERID REVOKED\n"
	},
	{
		"id": "ibm_vm",
		"category": CATEGORY_MAINFRAME,
		"os": "VM/CMS",
		"banner": """
    
    VM/370 ONLINE
    
    CENTRAL INSURANCE GROUP
    Claims Processing Division
    
""",
		"prompt": "LOGON ",
		"password_prompt": "",
		"login_response": "\nLOGON UNSUCCESSFUL--INCORRECT PASSWORD\nENTER LOGON:\n",
		"max_attempts": 3,
		"lockout_msg": "\nLOGON LOCKED OUT\n"
	},
	
	# ============================================================
	# HP SYSTEMS
	# ============================================================
	{
		"id": "hp3000_mfg",
		"category": CATEGORY_MINI,
		"os": "HP3000/MPE",
		"banner": """

    :::::::::::::::::::::::::::::::::::::::::
    ::  PRECISION MANUFACTURING INC.       ::
    ::  Inventory Control System           ::
    ::  HP 3000 Series 48                  ::
    :::::::::::::::::::::::::::::::::::::::::

    MPE V/E  G.03.02

""",
		"prompt": "ENTER USER NAME: ",
		"password_prompt": "ENTER PASSWORD: ",
		"login_response": "\nINCORRECT LOG-ON; TRY AGAIN\n\n",
		"max_attempts": 3,
		"lockout_msg": "\n**SESSION TERMINATED**\n"
	},
	
	# ============================================================
	# PRIME SYSTEMS
	# ============================================================
	{
		"id": "primos_eng",
		"category": CATEGORY_MINI,
		"os": "PRIMOS",
		"banner": """
    
    PRIMOS II  Rev 21.0
    Copyright (c) Prime Computer Inc.
    
    CONSOLIDATED ENGINEERING SERVICES
    CAD/CAM Division - Terminal 7
    
""",
		"prompt": "User id? ",
		"password_prompt": "Password? ",
		"login_response": "\nInvalid user id or password (login)\n\n",
		"max_attempts": 3,
		"lockout_msg": "\nConnection aborted.\n"
	},
	
	# ============================================================
	# BBS SYSTEMS
	# ============================================================
	{
		"id": "bbs_hacker",
		"category": CATEGORY_BBS,
		"os": "BBS",
		"organization": "The Underground Connection",
		"has_downloads": true,
		"downloads": ["wardialer", "wardialer_v2"],
		"guest_access": true,
		"banner": """

    ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
    █  THE UNDERGROUND CONNECTION  █
    █     "Information wants to be free"     █
    █  SysOp: The Phoenix  Node 1 of 3  █
    ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
    
    Running TBBS v2.1M  1200/2400 Baud

    Type GUEST to login as guest
    Type NEW to register
    
""",
		"prompt": "Enter your handle: ",
		"password_prompt": "Password: ",
		"login_response": "\nSorry, unknown user. New users call voice line.\n",
		"max_attempts": 1,
		"lockout_msg": ""
	},
	{
		"id": "bbs_local",
		"category": CATEGORY_BBS,
		"os": "BBS",
		"banner": """

    ==========================================
       SILICON VALLEY ONLINE
       Your Local Computer Connection!
       Node 2 - 2400 Baud
    ==========================================
    
    RBBS-PC v15.1C
    
""",
		"prompt": "What is your FIRST name? ",
		"password_prompt": "What is your LAST name? ",
		"login_response": "\nSearching user file...\nName not found.\n\nWould you like to register? (Y/N): ",
		"max_attempts": 1,
		"lockout_msg": ""
	},
	
	# ============================================================
	# UTILITY SYSTEMS (No password - direct access)
	# ============================================================
	{
		"id": "util_hvac",
		"category": CATEGORY_UTILITY,
		"os": "UTILITY",
		"banner": "",
		"menu": """

    -------------------------------------------
    JOHNSON CONTROLS METASYS
    Air Handling Unit #3 - East Wing
    -------------------------------------------
    
    Supply Temp:   72.4 F
    Return Temp:   74.1 F
    Fan Status:    RUNNING
    Filter:        OK
    
    Commands: STAT, TEMP, FAN, HELP, EXIT
    
    > """,
		"menu_response": "\nCommand not recognized. Type HELP for options.\n\n> "
	},
	{
		"id": "util_atm",
		"category": CATEGORY_UTILITY,
		"os": "UTILITY",
		"banner": "",
		"menu": """

    ╔══════════════════════════════════════╗
    ║     FIRST FEDERAL SAVINGS BANK       ║
    ║     ATM DIAGNOSTIC TERMINAL          ║
    ║     Unit: ATM-2847-BRANCH-14         ║
    ╚══════════════════════════════════════╝
    
    CASSETTE STATUS:
    $20 Bills:  [####______] 42%
    $10 Bills:  [########__] 81%
    $5 Bills:   [######____] 63%
    Receipt:    [##________] 24%  ** LOW **
    
    Last Transaction: 10:47:22 PM
    Total Today: $12,450.00 (127 trans)
    
    DIAGNOSTIC MENU - ENTER CODE: """,
		"menu_response": "\n** INVALID DIAGNOSTIC CODE **\n\nDIAGNOSTIC MENU - ENTER CODE: "
	},
	
	# ============================================================
	# DEAD CONNECTIONS
	# ============================================================
	{
		"id": "dead_1",
		"category": CATEGORY_DEAD,
		"os": "NONE",
		"banner": "",
		"response": "\n\n\n"
	},
	{
		"id": "dead_2",
		"category": CATEGORY_DEAD,
		"os": "NONE",
		"banner": "",
		"response": "\n@\n@\n@\n"
	},
	{
		"id": "dead_3",
		"category": CATEGORY_DEAD,
		"os": "NONE",
		"banner": "",
		"response": "\n????????\n"
	},
	{
		"id": "dead_4",
		"category": CATEGORY_DEAD,
		"os": "NONE",
		"banner": "",
		"response": "\n\nNO CARRIER\n"
	},
	{
		"id": "dead_5",
		"category": CATEGORY_DEAD,
		"os": "NONE",
		"banner": "",
		"response": "\n%$#%@#$%\n\nGARBAGE\n\n"
	},
]

# Probability weights for system types when assigning to modems
const CATEGORY_WEIGHTS = {
	CATEGORY_MAINFRAME: 20,
	CATEGORY_MINI: 10,
	CATEGORY_BBS: 10,
	CATEGORY_UTILITY: 20,
	CATEGORY_DEAD: 35,
	CATEGORY_AI: 5,
}


## Get a random system template
static func get_random_system() -> Dictionary:
	# First pick category based on weights
	var total_weight = 0
	for weight in CATEGORY_WEIGHTS.values():
		total_weight += weight
	
	var roll = randi() % total_weight
	var current = 0
	var selected_category = CATEGORY_MAINFRAME
	
	for cat in CATEGORY_WEIGHTS:
		current += CATEGORY_WEIGHTS[cat]
		if roll < current:
			selected_category = cat
			break
	
	# Skip AI category if no API key configured
	if selected_category == CATEGORY_AI:
		if not SettingsManager.has_openai_key():
			selected_category = CATEGORY_MAINFRAME
	
	# Get all systems in that category
	var category_systems: Array = []
	for sys in SYSTEMS:
		if sys.category == selected_category:
			category_systems.append(sys)
	
	# Pick random system from category
	if category_systems.size() > 0:
		return category_systems[randi() % category_systems.size()]
	
	return SYSTEMS[0]


## Get system by ID
static func get_system_by_id(id: String) -> Dictionary:
	for sys in SYSTEMS:
		if sys.id == id:
			return sys
	return {}
