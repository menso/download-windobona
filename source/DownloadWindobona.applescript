use AppleScript version "2.4"
use scripting additions
use framework "Cocoa"
use framework "AVFoundation"

property parent : class "NSObject"

property CURRENT_VERSION : "1.0.0"
property WINDOBONA_BASE : "https://bestellung.windobona.berlin/media/"
property GITHUB_REPO : "menso/download-windobona"

property win : missing value
property updateBanner : missing value

property stepLabel1 : missing value
property stepLabel2 : missing value
property stepLabel3 : missing value

property page1 : missing value
property page2 : missing value
property page3 : missing value

property urlTextView : missing value
property folderPathLabel : missing value
property startButton : missing value

property overallLabel : missing value
property overallBar : missing value
property ordersContainer : missing value
property summaryLabel : missing value
property closeButton : missing value

property queuedURLs : {}
property logPath : ""
property orderBars : {}
property orderStatusLabels : {}
property orderTotals : {}
property orderDone : {}
property orderSucceeded : {}
property orderFinished : {}

property destPath : ""
property pollTimer : missing value
property bashPID : ""
property stopButton : missing value

property rotationCams : {}
property rotationDegrees : {}
property rotWin : missing value
property rotButtons : {}

property greenColor : missing value
property grayColor : missing value
property redColor : missing value

on run
	set greenColor to current application's NSColor's colorWithCalibratedRed:0.0 green:0.55 blue:0.2 alpha:1.0
	set grayColor to current application's NSColor's grayColor()
	set redColor to current application's NSColor's colorWithCalibratedRed:0.7 green:0.1 blue:0.1 alpha:1.0

	set theApp to current application's NSApplication's sharedApplication()
	theApp's setActivationPolicy:0 -- NSApplicationActivationPolicyRegular
	my buildMenuBar()

	my buildWindow()
	my showStep(1)
	win's makeKeyAndOrderFront:me
	theApp's activateIgnoringOtherApps:true

	my checkForUpdate()

	theApp's |run|()
end run

-- ------------------------------------------------------------- UI build --

on buildMenuBar()
	-- a minimal app menu is all that's needed for macOS to wire up Cmd-Q
	-- (and other standard shortcuts) to this app; without any menu bar at
	-- all, there is nothing for Cmd-Q to trigger
	set mainMenu to current application's NSMenu's alloc()'s init()

	set appMenuItem to current application's NSMenuItem's alloc()'s init()
	mainMenu's addItem:appMenuItem
	set appMenu to current application's NSMenu's alloc()'s init()
	set quitItem to current application's NSMenuItem's alloc()'s initWithTitle:"Quit DownloadWindobona" action:"terminate:" keyEquivalent:"q"
	appMenu's addItem:quitItem
	appMenuItem's setSubmenu:appMenu

	-- without a real Edit menu, setting any custom main menu at all silences
	-- the standard Cmd-C/V/X/A/Z bindings that macOS otherwise wires up for
	-- free -- these items route to the focused text view via nil-target
	-- first-responder dispatch, exactly like a normal Cocoa app's Edit menu
	set editMenuItem to current application's NSMenuItem's alloc()'s init()
	mainMenu's addItem:editMenuItem
	set editMenu to current application's NSMenu's alloc()'s initWithTitle:"Edit"
	(editMenu's addItemWithTitle:"Undo" action:"undo:" keyEquivalent:"z")
	(editMenu's addItemWithTitle:"Redo" action:"redo:" keyEquivalent:"Z")
	editMenu's addItem:(current application's NSMenuItem's separatorItem())
	(editMenu's addItemWithTitle:"Cut" action:"cut:" keyEquivalent:"x")
	(editMenu's addItemWithTitle:"Copy" action:"copy:" keyEquivalent:"c")
	(editMenu's addItemWithTitle:"Paste" action:"paste:" keyEquivalent:"v")
	(editMenu's addItemWithTitle:"Select All" action:"selectAll:" keyEquivalent:"a")
	editMenuItem's setSubmenu:editMenu

	current application's NSApplication's sharedApplication()'s setMainMenu:mainMenu
end buildMenuBar

on buildWindow()
	set W to 580
	set H to 486
	set contentRect to current application's NSMakeRect(200, 200, W, H)
	set styleMask to 3 -- NSWindowStyleMaskTitled (1) + NSWindowStyleMaskClosable (2)
	set win to current application's NSWindow's alloc()'s initWithContentRect:contentRect styleMask:styleMask backing:2 defer:false -- 2 = NSBackingStoreBuffered
	win's setTitle:("DownloadWindobona " & CURRENT_VERSION)
	win's setReleasedWhenClosed:false
	win's setDelegate:me

	set contentView to win's contentView()

	-- update banner (hidden until an update is found)
	set updateBanner to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(20, 454, 540, 24))
	updateBanner's setBezelStyle:1 -- NSBezelStyleRounded
	updateBanner's setTarget:me
	updateBanner's setAction:"openReleasePage:"
	updateBanner's setHidden:true
	contentView's addSubview:updateBanner

	-- stepper bar
	set stepLabel1 to my makeLabel("1  Add URLs", 20, 420, 170, 24, false)
	set arrow1 to my makeLabel("→", 192, 420, 24, 24, false)
	set stepLabel2 to my makeLabel("2  Select Folder", 218, 420, 170, 24, false)
	set arrow2 to my makeLabel("→", 390, 420, 24, 24, false)
	set stepLabel3 to my makeLabel("3  Download Progress", 416, 420, 170, 24, false)
	contentView's addSubview:stepLabel1
	contentView's addSubview:arrow1
	contentView's addSubview:stepLabel2
	contentView's addSubview:arrow2
	contentView's addSubview:stepLabel3

	-- page 1: add URLs
	set page1 to current application's NSView's alloc()'s initWithFrame:(current application's NSMakeRect(20, 60, 540, 350))
	set instr1 to my makeLabel("Paste one or more Windobona order URLs, one per line:", 0, 320, 540, 20, false)
	page1's addSubview:instr1

	set exampleLabel to my makeLabel("e.g. " & WINDOBONA_BASE & "«code»  — or just paste the «code» part by itself", 0, 298, 540, 18, false)
	exampleLabel's setTextColor:grayColor
	exampleLabel's setFont:(current application's NSFont's systemFontOfSize:11)
	page1's addSubview:exampleLabel

	set urlScroll to current application's NSScrollView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 40, 540, 250))
	urlScroll's setHasVerticalScroller:true
	urlScroll's setBorderType:2 -- NSBezelBorder
	set urlTextView to current application's NSTextView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 540, 270))
	urlScroll's setDocumentView:urlTextView
	page1's addSubview:urlScroll

	set next1 to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(440, 0, 100, 32))
	next1's setTitle:"Next"
	next1's setBezelStyle:1 -- NSBezelStyleRounded
	next1's setTarget:me
	next1's setAction:"step1Next:"
	page1's addSubview:next1

	contentView's addSubview:page1

	-- page 2: destination folder
	set page2 to current application's NSView's alloc()'s initWithFrame:(current application's NSMakeRect(20, 60, 540, 350))
	set instr2 to my makeLabel("Choose a destination folder for the downloaded videos:", 0, 320, 500, 24, false)
	page2's addSubview:instr2

	set folderPathLabel to my makeLabel("(no folder selected)", 0, 280, 500, 20, false)
	folderPathLabel's setTextColor:grayColor
	page2's addSubview:folderPathLabel

	set chooseBtn to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(0, 240, 180, 32))
	chooseBtn's setTitle:"Choose Folder…"
	chooseBtn's setBezelStyle:1 -- NSBezelStyleRounded
	chooseBtn's setTarget:me
	chooseBtn's setAction:"chooseFolder:"
	page2's addSubview:chooseBtn

	set back2 to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 100, 32))
	back2's setTitle:"Back"
	back2's setBezelStyle:1 -- NSBezelStyleRounded
	back2's setTarget:me
	back2's setAction:"step2Back:"
	page2's addSubview:back2

	set startButton to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(440, 0, 100, 32))
	startButton's setTitle:"Start"
	startButton's setBezelStyle:1 -- NSBezelStyleRounded
	startButton's setTarget:me
	startButton's setAction:"step2Start:"
	startButton's setEnabled:false
	page2's addSubview:startButton

	contentView's addSubview:page2
	page2's setHidden:true

	-- page 3: download progress
	set page3 to current application's NSView's alloc()'s initWithFrame:(current application's NSMakeRect(20, 60, 540, 350))

	set overallLabel to my makeLabel("Overall Progress: 0%  (0 of 0)", 0, 330, 540, 20, false)
	page3's addSubview:overallLabel

	set overallBar to current application's NSProgressIndicator's alloc()'s initWithFrame:(current application's NSMakeRect(0, 305, 540, 18))
	overallBar's setIndeterminate:false
	overallBar's setMinValue:0
	overallBar's setMaxValue:100
	overallBar's setDoubleValue:0
	page3's addSubview:overallBar

	set ordersScroll to current application's NSScrollView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 40, 540, 255))
	ordersScroll's setHasVerticalScroller:true
	ordersScroll's setBorderType:2 -- NSBezelBorder
	set ordersContainer to current application's NSView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 520, 10))
	ordersScroll's setDocumentView:ordersContainer
	page3's addSubview:ordersScroll

	set summaryLabel to my makeLabel("", 0, 0, 420, 55, false)
	(summaryLabel's cell())'s setWraps:true
	summaryLabel's setHidden:true
	page3's addSubview:summaryLabel

	set closeButton to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(440, 0, 100, 32))
	closeButton's setTitle:"Close"
	closeButton's setBezelStyle:1 -- NSBezelStyleRounded
	closeButton's setTarget:me
	closeButton's setAction:"closeClicked:"
	closeButton's setHidden:true
	page3's addSubview:closeButton

	set stopButton to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(440, 0, 100, 32))
	stopButton's setTitle:"Stop"
	stopButton's setBezelStyle:1 -- NSBezelStyleRounded
	stopButton's setTarget:me
	stopButton's setAction:"stopClicked:"
	stopButton's setHidden:true
	page3's addSubview:stopButton

	contentView's addSubview:page3
	page3's setHidden:true
end buildWindow

on makeLabel(theText, x, y, w, h, isBold)
	set lbl to current application's NSTextField's alloc()'s initWithFrame:(current application's NSMakeRect(x, y, w, h))
	lbl's setStringValue:theText
	lbl's setBezeled:false
	lbl's setDrawsBackground:false
	lbl's setEditable:false
	lbl's setSelectable:false
	if isBold then
		lbl's setFont:(current application's NSFont's boldSystemFontOfSize:13)
	else
		lbl's setFont:(current application's NSFont's systemFontOfSize:13)
	end if
	return lbl
end makeLabel

on showStep(n)
	page1's setHidden:(n is not 1)
	page2's setHidden:(n is not 2)
	page3's setHidden:(n is not 3)

	if n is 1 then
		stepLabel1's setStringValue:"▶  1  Add URLs"
		stepLabel1's setTextColor:greenColor
		stepLabel1's setFont:(current application's NSFont's boldSystemFontOfSize:13)
	else
		stepLabel1's setStringValue:"✓  1  Add URLs"
		stepLabel1's setTextColor:grayColor
		stepLabel1's setFont:(current application's NSFont's systemFontOfSize:13)
	end if

	if n is 2 then
		stepLabel2's setStringValue:"▶  2  Select Folder"
		stepLabel2's setTextColor:greenColor
		stepLabel2's setFont:(current application's NSFont's boldSystemFontOfSize:13)
	else if n > 2 then
		stepLabel2's setStringValue:"✓  2  Select Folder"
		stepLabel2's setTextColor:grayColor
		stepLabel2's setFont:(current application's NSFont's systemFontOfSize:13)
	else
		stepLabel2's setStringValue:"   2  Select Folder"
		stepLabel2's setTextColor:grayColor
		stepLabel2's setFont:(current application's NSFont's systemFontOfSize:13)
	end if

	if n is 3 then
		stepLabel3's setStringValue:"▶  3  Download Progress"
		stepLabel3's setTextColor:greenColor
		stepLabel3's setFont:(current application's NSFont's boldSystemFontOfSize:13)
	else
		stepLabel3's setStringValue:"   3  Download Progress"
		stepLabel3's setTextColor:grayColor
		stepLabel3's setFont:(current application's NSFont's systemFontOfSize:13)
	end if
end showStep

-- -------------------------------------------------------------- actions --

on step1Next:sender
	set rawText to (urlTextView's |string|()) as text
	set theLines to paragraphs of rawText
	set cleanURLs to {}
	repeat with l in theLines
		set t to my trimText(l as text)
		if t is not "" then
			if t does not start with "http" then set t to WINDOBONA_BASE & t
			set end of cleanURLs to t
		end if
	end repeat

	if (count of cleanURLs) is 0 then
		my showAlert("No URLs entered", "Paste at least one Windobona order URL, one per line.")
		return
	end if

	set queuedURLs to cleanURLs
	my loadRotationPrefs()
	my askRotationChoice()
	my showStep(2)
end step1Next:

on showRotationEditor()
	set cams to my detectCamerasAcrossURLs(queuedURLs)
	if (count of cams) is 0 then
		-- couldn't reach the server to find out which cameras exist; fall
		-- back to the known default range rather than showing an empty table
		set cams to {0, 1, 2, 3, 4}
	end if

	set colLabels to {"No rotation", "90° CW", "90° CCW", "180°"}
	set colDegrees to {0, 90, 270, 180}
	set colW to 110
	set labelW to 90
	set rowH to 30
	set gridW to labelW + (colW * 4)
	set gridH to rowH * ((count of cams) + 1)

	set gridView to current application's NSView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, gridW, gridH))

	repeat with c from 1 to 4
		set hdr to my makeLabel(item c of colLabels, labelW + ((c - 1) * colW), gridH - rowH, colW, 20, true)
		gridView's addSubview:hdr
	end repeat

	set rotButtons to {}
	set rowIdx to 0
	repeat with camN in cams
		set rowIdx to rowIdx + 1
		set rowTop to gridH - rowH - (rowIdx * rowH)
		set camLabel to my makeLabel("Camera " & camN, 0, rowTop + 4, labelW, 20, false)
		gridView's addSubview:camLabel

		set rowContainer to current application's NSView's alloc()'s initWithFrame:(current application's NSMakeRect(labelW, rowTop, colW * 4, rowH))
		gridView's addSubview:rowContainer

		set curDeg to my degreesForCam(camN)
		set rowButtonSet to {}
		repeat with c from 1 to 4
			set rb to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect((c - 1) * colW + colW / 2 - 10, 4, 20, 20))
			rb's setButtonType:4 -- NSButtonTypeRadio
			rb's setTitle:""
			if curDeg is (item c of colDegrees) then
				rb's setState:1
			else
				rb's setState:0
			end if
			rowContainer's addSubview:rb
			set end of rowButtonSet to rb
		end repeat
		set end of rotButtons to {camera:camN, buttons:rowButtonSet}
	end repeat

	set theAlert to current application's NSAlert's alloc()'s init()
	theAlert's setMessageText:"Customize Rotations"
	theAlert's setInformativeText:"Pick one rotation per camera."
	(theAlert's addButtonWithTitle:"Save")
	(theAlert's addButtonWithTitle:"Cancel")
	theAlert's setAccessoryView:gridView

	set theResponse to theAlert's runModal() as integer
	if theResponse is 1000 then
		set rotationCams to {}
		set rotationDegrees to {}
		repeat with rowRec in rotButtons
			set camN to camera of rowRec
			set btns to buttons of rowRec
			set chosenDeg to 0
			repeat with c from 1 to 4
				if ((item c of btns)'s state() as integer) is 1 then
					set chosenDeg to item c of colDegrees
				end if
			end repeat
			set end of rotationCams to camN
			set end of rotationDegrees to chosenDeg
		end repeat
		my saveRotationPrefs()
	end if
end showRotationEditor

on askRotationChoice()
	set theAlert to current application's NSAlert's alloc()'s init()
	theAlert's setMessageText:"Use default rotation settings?"
	theAlert's setInformativeText:"Camera 4 is normally mounted sideways and gets rotated 90° automatically; every other camera is left as-is. Choose Customize to set this per camera instead."
	(theAlert's addButtonWithTitle:"Use Defaults")
	(theAlert's addButtonWithTitle:"Customize Rotations…")
	set theResponse to theAlert's runModal() as integer
	-- NSAlertFirstButtonReturn = 1000, NSAlertSecondButtonReturn = 1001
	if theResponse is 1000 then
		my saveRotationPrefs()
	else
		my showRotationEditor()
	end if
end askRotationChoice

on step2Back:sender
	my showStep(1)
end step2Back:

on chooseFolder:sender
	set thePanel to current application's NSOpenPanel's openPanel()
	thePanel's setCanChooseDirectories:true
	thePanel's setCanChooseFiles:false
	thePanel's setAllowsMultipleSelection:false
	set theResult to thePanel's runModal()
	if theResult is 1 then -- NSModalResponseOK
		set theURL to (thePanel's URLs())'s firstObject()
		set destPath to (theURL's |path|()) as text
		folderPathLabel's setStringValue:destPath
		folderPathLabel's setTextColor:(current application's NSColor's blackColor())
		startButton's setEnabled:true
	end if
end chooseFolder:

on step2Start:sender
	if destPath is "" then return

	set cp to "init"
	try
		set cp to "date seed"
		set tsSeed to do shell script "date +%s"
		set logPath to "/tmp/downloadwindobona_" & tsSeed & ".log"
		set orderBars to {}
		set orderStatusLabels to {}
		set orderTotals to {}
		set orderDone to {}
		set orderSucceeded to {}
		set orderFinished to {}

		set cp to "container frame"
		set rowH to 54
		set n to count of queuedURLs
		set containerH to n * rowH
		if containerH < 255 then set containerH to 255
		ordersContainer's setFrame:(current application's NSMakeRect(0, 0, 520, containerH))

		set urlArgs to ""
		repeat with i from 1 to n
			set cp to "loop " & i & ": setup"
			set u to item i of queuedURLs
			set end of orderTotals to 0
			set end of orderDone to 0
			set end of orderSucceeded to 0
			set end of orderFinished to false

			set rowTop to containerH - (i * rowH)
			set shortURL to my shortenURL(u)

			set cp to "loop " & i & ": label"
			set rowLabel to my makeLabel("Order " & i & " — " & shortURL, 0, rowTop + 32, 520, 18, false)
			ordersContainer's addSubview:rowLabel

			set cp to "loop " & i & ": progress bar"
			set rowBar to current application's NSProgressIndicator's alloc()'s initWithFrame:(current application's NSMakeRect(0, rowTop + 10, 390, 16))
			rowBar's setIndeterminate:false
			rowBar's setMinValue:0
			rowBar's setMaxValue:100
			rowBar's setDoubleValue:0
			ordersContainer's addSubview:rowBar
			set end of orderBars to rowBar

			set cp to "loop " & i & ": status label"
			set rowStatus to my makeLabel("queued…", 400, rowTop + 10, 120, 16, false)
			ordersContainer's addSubview:rowStatus
			set end of orderStatusLabels to rowStatus

			set urlArgs to urlArgs & " " & quoted form of u
		end repeat

		set cp to "launch"
		set cmd to "nohup /bin/bash " & quoted form of my scriptPath() & " " & quoted form of destPath & urlArgs & " > " & quoted form of logPath & " 2>&1 < /dev/null & echo $!"
		set bashPID to do shell script cmd

		set cp to "showStep 3"
		my showStep(3)
		stopButton's setHidden:false

		set cp to "start timer"
		set pollTimer to current application's NSTimer's scheduledTimerWithTimeInterval:0.5 target:me selector:"pollProgress:" userInfo:(missing value) repeats:true
	on error errMsg number errNum
		my showAlert("Start failed at [" & cp & "] (" & errNum & ")", errMsg)
	end try
end step2Start:

on pollProgress:sender
	set n to count of queuedURLs
	set logText to my readFile(logPath)
	set allDone to true

	repeat with i from 1 to n
		if (item i of orderFinished) is false then
			set allDone to false
			if logText is not "" then
				set finalLine to my lastLineStartingWith(logText, "FINAL order=" & i & " ")
				set errorLine to my lastLineStartingWith(logText, "ERROR order=" & i & " ")
				set stateLine to my lastLineStartingWith(logText, "STATE order=" & i & " ")

				set theBar to item i of orderBars
				set theStatus to item i of orderStatusLabels

				if finalLine is not "" then
					-- "done" in the FINAL line is already the succeeded count
					set dN to my valueFor(finalLine, "done")
					set tN to my valueFor(finalLine, "total")
					set item i of orderDone to dN
					set item i of orderSucceeded to dN
					set item i of orderTotals to tN
					theBar's setDoubleValue:100
					theStatus's setStringValue:("Done " & dN & "/" & tN)
					theStatus's setTextColor:greenColor
					set item i of orderFinished to true
				else if errorLine is not "" then
					theStatus's setStringValue:"Error"
					theStatus's setTextColor:redColor
					set item i of orderFinished to true
				else if stateLine is not "" then
					set tN to my valueFor(stateLine, "total")
					set dN to my valueFor(stateLine, "done")
					set sN to my valueFor(stateLine, "succeeded")
					set aN to my valueFor(stateLine, "active")
					set item i of orderTotals to tN
					set item i of orderDone to dN
					set item i of orderSucceeded to sN
					if tN > 0 then
						set pct to (dN / tN) * 100
						theBar's setDoubleValue:pct
					end if
					if aN > 0 then
						theStatus's setStringValue:((sN as text) & "/" & (tN as text) & " • " & (aN as text) & " active")
					else
						theStatus's setStringValue:((sN as text) & "/" & (tN as text))
					end if
				end if
			end if
		end if
	end repeat

	set totalAll to 0
	set doneAll to 0
	set succeededAll to 0
	repeat with i from 1 to n
		set totalAll to totalAll + (item i of orderTotals)
		set doneAll to doneAll + (item i of orderDone)
		set succeededAll to succeededAll + (item i of orderSucceeded)
	end repeat

	if totalAll > 0 then
		-- the bar fills based on total processed (so it reliably reaches
		-- 100%), but the number shown is successful downloads only
		set overallPct to (doneAll / totalAll) * 100
		overallBar's setDoubleValue:overallPct
		set pctInt to round overallPct
		overallLabel's setStringValue:("Overall Progress: " & pctInt & "%  (" & succeededAll & " of " & totalAll & ")")
	end if

	if allDone then
		pollTimer's invalidate()
		overallLabel's setStringValue:"Applying rotation settings…"
		set rotatedCount to my applyRotations(destPath)
		set rotSuffix to ""
		if rotatedCount > 0 then set rotSuffix to return & "Rotated " & rotatedCount & " video(s) per your settings."
		summaryLabel's setStringValue:("Downloaded " & succeededAll & " of " & totalAll & " videos." & rotSuffix & return & "Saved to: " & destPath)
		summaryLabel's setHidden:false
		stopButton's setHidden:true
		closeButton's setHidden:false
	end if
end pollProgress:

on applyRotations(rootPath)
	set rotatedCount to 0
	repeat with idx from 1 to (count of rotationCams)
		set camN to item idx of rotationCams
		set deg to item idx of rotationDegrees
		if deg is not 0 then
			try
				set findCmd to "find " & quoted form of rootPath & " -type f -name " & quoted form of ("*_cam" & camN & ".mp4")
				set fileList to do shell script findCmd
				repeat with fPath in (paragraphs of fileList)
					set fPath to fPath as text
					if fPath is not "" then
						if my rotateFile(fPath, deg) then set rotatedCount to rotatedCount + 1
					end if
				end repeat
			end try
		end if
	end repeat
	return rotatedCount
end applyRotations

on closeClicked:sender
	current application's NSApplication's sharedApplication()'s terminate:me
end closeClicked:

on stopClicked:sender
	if pollTimer is not missing value then pollTimer's invalidate()
	if bashPID is not "" then
		try
			do shell script "kill " & bashPID & " 2>/dev/null; sleep 0.3; kill -9 " & bashPID & " 2>/dev/null; pkill -9 -f " & quoted form of my scriptPath() & " 2>/dev/null"
		end try
	end if

	set succeededAll to 0
	set totalAll to 0
	repeat with i from 1 to (count of queuedURLs)
		if (item i of orderFinished) is false then
			set item i of orderFinished to true
			(item i of orderStatusLabels)'s setStringValue:"Stopped"
			(item i of orderStatusLabels)'s setTextColor:redColor
		end if
		set succeededAll to succeededAll + (item i of orderSucceeded)
		set totalAll to totalAll + (item i of orderTotals)
	end repeat

	summaryLabel's setStringValue:("Stopped after " & succeededAll & " of " & totalAll & " videos." & return & "Already-downloaded files are kept — re-running the same order(s) will pick up where this left off." & return & "Saved to: " & destPath)
	summaryLabel's setHidden:false
	stopButton's setHidden:true
	closeButton's setHidden:false
end stopClicked:

on windowWillClose:aNotification
	current application's NSApplication's sharedApplication()'s terminate:me
end windowWillClose:

on openReleasePage:sender
	current application's NSWorkspace's sharedWorkspace()'s openURL:(current application's NSURL's URLWithString:("https://github.com/" & GITHUB_REPO & "/releases/latest"))
end openReleasePage:

-- --------------------------------------------------------------- update --

on checkForUpdate()
	try
		set theURL to current application's NSURL's URLWithString:("https://api.github.com/repos/" & GITHUB_REPO & "/releases/latest")
		set theRequest to current application's NSMutableURLRequest's requestWithURL:theURL
		theRequest's setTimeoutInterval:4.0
		set theData to current application's NSURLConnection's sendSynchronousRequest:theRequest returningResponse:(missing value) |error|:(missing value)
		if theData is missing value then return

		set jsonStr to (current application's NSString's alloc()'s initWithData:theData encoding:4) as text -- 4 = NSUTF8StringEncoding
		set tagValue to my extractJSONString(jsonStr, "tag_name")
		if tagValue is "" then return

		set cleanTag to tagValue
		if cleanTag starts with "v" then set cleanTag to text 2 thru -1 of cleanTag

		if cleanTag is not CURRENT_VERSION then
			updateBanner's setTitle:("⬆ Update available: " & tagValue & " — click to view on GitHub")
			updateBanner's setHidden:false
		end if
	end try
end checkForUpdate

on extractJSONString(jsonStr, key)
	set searchPattern to "\"" & key & "\":\""
	set AppleScript's text item delimiters to searchPattern
	set parts to text items of jsonStr
	set AppleScript's text item delimiters to ""
	if (count of parts) < 2 then return ""
	set afterKey to item 2 of parts
	set AppleScript's text item delimiters to "\""
	set valueParts to text items of afterKey
	set AppleScript's text item delimiters to ""
	if (count of valueParts) < 1 then return ""
	return item 1 of valueParts
end extractJSONString

-- -------------------------------------------------------------- helpers --

on rotationPrefsPath()
	return (POSIX path of (path to home folder)) & "Library/Application Support/DownloadWindobona/rotation.conf"
end rotationPrefsPath

on loadRotationPrefs()
	-- defaults: cam4 gets 90deg (clockwise), everything else 0 -- matches
	-- how these cameras are physically mounted in the typical setup
	set rotationCams to {0, 1, 2, 3, 4}
	set rotationDegrees to {0, 0, 0, 0, 90}

	set p to my rotationPrefsPath()
	set fileText to my readFile(p)
	if fileText is "" then return

	repeat with l in (paragraphs of fileText)
		set l to l as text
		if l contains "=" then
			set AppleScript's text item delimiters to "="
			set parts to text items of l
			set AppleScript's text item delimiters to ""
			if (count of parts) is 2 then
				set camText to item 1 of parts
				if camText begins with "cam" then
					try
						set camNum to (text 4 thru -1 of camText) as integer
						set degNum to (item 2 of parts) as integer
						repeat with idx from 1 to (count of rotationCams)
							if (item idx of rotationCams) is camNum then
								set item idx of rotationDegrees to degNum
							end if
						end repeat
						if camNum is not in rotationCams then
							set end of rotationCams to camNum
							set end of rotationDegrees to degNum
						end if
					end try
				end if
			end if
		end if
	end repeat
end loadRotationPrefs

on saveRotationPrefs()
	set p to my rotationPrefsPath()
	set dirPath to (POSIX path of (path to home folder)) & "Library/Application Support/DownloadWindobona"
	do shell script "mkdir -p " & quoted form of dirPath

	set outLines to {}
	repeat with idx from 1 to (count of rotationCams)
		set end of outLines to ("cam" & (item idx of rotationCams) & "=" & (item idx of rotationDegrees))
	end repeat
	set outText to my joinList(outLines, return)

	set nsText to current application's NSString's stringWithString:outText
	(nsText's writeToFile:p atomically:true encoding:4 |error|:(missing value)) -- 4 = NSUTF8StringEncoding
end saveRotationPrefs

on degreesForCam(camNum)
	repeat with idx from 1 to (count of rotationCams)
		if (item idx of rotationCams) is camNum then return (item idx of rotationDegrees)
	end repeat
	return 0
end degreesForCam

on detectCamerasAcrossURLs(urlList)
	-- a quick, synchronous fetch+parse (no downloads) just to find which
	-- camera numbers this set of orders actually uses, for the rotation
	-- customize table
	set shellLines to {}
	repeat with u in urlList
		set end of shellLines to ("curl -sS -X POST -H 'Content-Type: application/json' --max-time 15 " & quoted form of (u as text) & " 2>/dev/null")
	end repeat
	-- build the API url per order the same way the download engine does
	set camSet to {}
	repeat with u in urlList
		set uText to u as text
		set secText to do shell script "printf '%s' " & quoted form of uText & " | sed -E 's#/+$##' | sed -E 's#.*/##'"
		set hostText to do shell script "printf '%s' " & quoted form of uText & " | sed -E 's#^(https?://[^/]+).*#\\1#'"
		set apiURL to hostText & "/api/media?sec=" & secText
		try
			set jsonText to do shell script "curl -sS -X POST -H 'Content-Type: application/json' --max-time 15 " & quoted form of apiURL
			set camsText to do shell script "printf '%s' " & quoted form of jsonText & " | grep -oE '_cam[0-9]+_' | sed -E 's/_cam([0-9]+)_/\\1/' | sort -nu"
			repeat with camLine in (paragraphs of camsText)
				set camLine to camLine as text
				if camLine is not "" then
					set camN to camLine as integer
					if camN is not in camSet then set end of camSet to camN
				end if
			end repeat
		end try
	end repeat
	return camSet
end detectCamerasAcrossURLs

on scriptPath()
	set bundlePath to (current application's NSBundle's mainBundle()'s bundlePath()) as text
	return bundlePath & "/Contents/Resources/download_windobona.sh"
end scriptPath

on readFile(p)
	try
		set nsStr to current application's NSString's stringWithContentsOfFile:p encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
		if nsStr is missing value then return ""
		return nsStr as text
	on error
		return ""
	end try
end readFile

on rotateFile(filePath, degrees)
	-- rewrites the video's orientation metadata only -- a passthrough
	-- export, so there is no re-encoding or quality loss, just a fast remux
	if degrees is 0 then return true

	try
		set srcURL to current application's NSURL's fileURLWithPath:filePath
		set asset to current application's AVURLAsset's URLAssetWithURL:srcURL options:(missing value)
		set videoTracks to asset's tracksWithMediaType:(current application's AVMediaTypeVideo)
		if (count of videoTracks) is 0 then return false
		set vTrack to item 1 of videoTracks
		set trackSize to vTrack's naturalSize()
		set w to width of trackSize
		set h to height of trackSize

		set composition to current application's AVMutableComposition's composition()
		set compVideoTrack to composition's addMutableTrackWithMediaType:(current application's AVMediaTypeVideo) preferredTrackID:(current application's kCMPersistentTrackID_Invalid)
		set assetDuration to asset's duration()
		set fullRange to current application's CMTimeRangeMake(current application's kCMTimeZero, assetDuration)
		compVideoTrack's insertTimeRange:fullRange ofTrack:vTrack atTime:(current application's kCMTimeZero) |error|:(missing value)

		if degrees is 90 then
			set theTransform to current application's CGAffineTransformMake(0, 1, -1, 0, h, 0)
		else if degrees is 270 then
			set theTransform to current application's CGAffineTransformMake(0, -1, 1, 0, 0, w)
		else if degrees is 180 then
			set theTransform to current application's CGAffineTransformMake(-1, 0, 0, -1, w, h)
		else
			set theTransform to vTrack's preferredTransform()
		end if
		compVideoTrack's setPreferredTransform:theTransform

		set audioTracks to asset's tracksWithMediaType:(current application's AVMediaTypeAudio)
		if (count of audioTracks) > 0 then
			set aTrack to item 1 of audioTracks
			set compAudioTrack to composition's addMutableTrackWithMediaType:(current application's AVMediaTypeAudio) preferredTrackID:(current application's kCMPersistentTrackID_Invalid)
			compAudioTrack's insertTimeRange:fullRange ofTrack:aTrack atTime:(current application's kCMTimeZero) |error|:(missing value)
		end if

		set tmpPath to filePath & ".rotating.mp4"
		try
			current application's NSFileManager's defaultManager()'s removeItemAtPath:tmpPath |error|:(missing value)
		end try

		set exportSession to current application's AVAssetExportSession's alloc()'s initWithAsset:composition presetName:(current application's AVAssetExportPresetPassthrough)
		exportSession's setOutputURL:(current application's NSURL's fileURLWithPath:tmpPath)
		exportSession's setOutputFileType:(current application's AVFileTypeMPEG4)
		exportSession's exportAsynchronouslyWithCompletionHandler:(missing value)

		set isDone to false
		repeat until isDone
			set theStatus to exportSession's status() as integer
			if theStatus is greater than or equal to 3 then
				set isDone to true
			else
				delay 0.2
			end if
		end repeat

		if theStatus is 3 then
			current application's NSFileManager's defaultManager()'s removeItemAtPath:filePath |error|:(missing value)
			current application's NSFileManager's defaultManager()'s moveItemAtPath:tmpPath toPath:filePath |error|:(missing value)
			return true
		else
			try
				current application's NSFileManager's defaultManager()'s removeItemAtPath:tmpPath |error|:(missing value)
			end try
			return false
		end if
	on error
		return false
	end try
end rotateFile

on trimText(t)
	set t to t as text
	repeat while t starts with " "
		set t to text 2 thru -1 of t
	end repeat
	repeat while t ends with " "
		set t to text 1 thru -2 of t
	end repeat
	return t
end trimText

on shortenURL(u)
	if (length of u) > 55 then
		return (text 1 thru 30 of u) & "…" & (text -20 thru -1 of u)
	else
		return u
	end if
end shortenURL

on lastLineStartingWith(theText, prefix)
	set theLines to paragraphs of theText
	set foundLine to ""
	repeat with l in theLines
		if l begins with prefix then set foundLine to l as string
	end repeat
	return foundLine
end lastLineStartingWith

on valueFor(lineText, key)
	if lineText is "" then return 0
	set searchKey to key & "="
	set AppleScript's text item delimiters to " "
	set toks to text items of lineText
	set AppleScript's text item delimiters to ""
	repeat with t in toks
		set t to t as string
		if t begins with searchKey then
			if (length of t) = (length of searchKey) then return 0
			set valueText to text ((length of searchKey) + 1) thru (length of t) of t
			return valueText as integer
		end if
	end repeat
	return 0
end valueFor

on showAlert(titleText, msgText)
	set theAlert to current application's NSAlert's alloc()'s init()
	theAlert's setMessageText:titleText
	theAlert's setInformativeText:msgText
	theAlert's runModal()
end showAlert
