use AppleScript version "2.4"
use scripting additions
use framework "Cocoa"

property parent : class "NSObject"

property CURRENT_VERSION : "1.0.0"
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
property logPaths : {}
property orderBars : {}
property orderStatusLabels : {}
property orderTotals : {}
property orderDone : {}
property orderFinished : {}

property destPath : ""
property pollTimer : missing value

property greenColor : missing value
property grayColor : missing value
property redColor : missing value

on run
	set greenColor to current application's NSColor's colorWithCalibratedRed:0.0 green:0.55 blue:0.2 alpha:1.0
	set grayColor to current application's NSColor's grayColor()
	set redColor to current application's NSColor's colorWithCalibratedRed:0.7 green:0.1 blue:0.1 alpha:1.0

	set theApp to current application's NSApplication's sharedApplication()
	theApp's setActivationPolicy:(current application's NSApplicationActivationPolicyRegular)

	my buildWindow()
	my showStep(1)
	win's makeKeyAndOrderFront:me
	theApp's activateIgnoringOtherApps:true

	my checkForUpdate()

	theApp's |run|()
end run

-- ------------------------------------------------------------- UI build --

on buildWindow()
	set W to 580
	set H to 486
	set contentRect to current application's NSMakeRect(200, 200, W, H)
	set styleMask to (current application's NSWindowStyleMaskTitled) + (current application's NSWindowStyleMaskClosable)
	set win to current application's NSWindow's alloc()'s initWithContentRect:contentRect styleMask:styleMask backing:(current application's NSBackingStoreBuffered) defer:false
	win's setTitle:("DownloadWindobona " & CURRENT_VERSION)
	win's setReleasedWhenClosed:false
	win's setDelegate:me

	set contentView to win's contentView()

	-- update banner (hidden until an update is found)
	set updateBanner to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(20, 454, 540, 24))
	updateBanner's setBezelStyle:(current application's NSBezelStyleRounded)
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
	set instr1 to my makeLabel("Paste one or more Windobona order URLs, one per line:", 0, 320, 500, 24, false)
	page1's addSubview:instr1

	set urlScroll to current application's NSScrollView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 40, 540, 270))
	urlScroll's setHasVerticalScroller:true
	urlScroll's setBorderType:(current application's NSBezelBorder)
	set urlTextView to current application's NSTextView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 540, 270))
	urlScroll's setDocumentView:urlTextView
	page1's addSubview:urlScroll

	set next1 to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(440, 0, 100, 32))
	next1's setTitle:"Next"
	next1's setBezelStyle:(current application's NSBezelStyleRounded)
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
	chooseBtn's setBezelStyle:(current application's NSBezelStyleRounded)
	chooseBtn's setTarget:me
	chooseBtn's setAction:"chooseFolder:"
	page2's addSubview:chooseBtn

	set back2 to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 100, 32))
	back2's setTitle:"Back"
	back2's setBezelStyle:(current application's NSBezelStyleRounded)
	back2's setTarget:me
	back2's setAction:"step2Back:"
	page2's addSubview:back2

	set startButton to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(440, 0, 100, 32))
	startButton's setTitle:"Start"
	startButton's setBezelStyle:(current application's NSBezelStyleRounded)
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
	ordersScroll's setBorderType:(current application's NSBezelBorder)
	set ordersContainer to current application's NSView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 520, 10))
	ordersScroll's setDocumentView:ordersContainer
	page3's addSubview:ordersScroll

	set summaryLabel to my makeLabel("", 0, 5, 420, 30, false)
	summaryLabel's setHidden:true
	page3's addSubview:summaryLabel

	set closeButton to current application's NSButton's alloc()'s initWithFrame:(current application's NSMakeRect(440, 0, 100, 32))
	closeButton's setTitle:"Close"
	closeButton's setBezelStyle:(current application's NSBezelStyleRounded)
	closeButton's setTarget:me
	closeButton's setAction:"closeClicked:"
	closeButton's setHidden:true
	page3's addSubview:closeButton

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
		if t is not "" then set end of cleanURLs to t
	end repeat

	if (count of cleanURLs) is 0 then
		my showAlert("No URLs entered", "Paste at least one Windobona order URL, one per line.")
		return
	end if

	set queuedURLs to cleanURLs
	my showStep(2)
end step1Next:

on step2Back:sender
	my showStep(1)
end step2Back:

on chooseFolder:sender
	set thePanel to current application's NSOpenPanel's openPanel()
	thePanel's setCanChooseDirectories:true
	thePanel's setCanChooseFiles:false
	thePanel's setAllowsMultipleSelection:false
	set theResult to thePanel's runModal()
	if theResult is (current application's NSModalResponseOK) then
		set theURL to (thePanel's URLs())'s firstObject()
		set destPath to (theURL's |path|()) as text
		folderPathLabel's setStringValue:destPath
		folderPathLabel's setTextColor:(current application's NSColor's blackColor())
		startButton's setEnabled:true
	end if
end chooseFolder:

on step2Start:sender
	if destPath is "" then return

	set tsSeed to do shell script "date +%s"
	set logPaths to {}
	set orderBars to {}
	set orderStatusLabels to {}
	set orderTotals to {}
	set orderDone to {}
	set orderFinished to {}

	set rowH to 54
	set n to count of queuedURLs
	set containerH to n * rowH
	if containerH < 255 then set containerH to 255
	ordersContainer's setFrame:(current application's NSMakeRect(0, 0, 520, containerH))

	repeat with i from 1 to n
		set u to item i of queuedURLs
		set lp to "/tmp/downloadwindobona_" & tsSeed & "_" & i & ".log"
		set end of logPaths to lp
		set end of orderTotals to 0
		set end of orderDone to 0
		set end of orderFinished to false

		set rowTop to containerH - (i * rowH)
		set shortURL to my shortenURL(u)

		set rowLabel to my makeLabel("Order " & i & " — " & shortURL, 0, rowTop + 32, 520, 18, false)
		ordersContainer's addSubview:rowLabel

		set rowBar to current application's NSProgressIndicator's alloc()'s initWithFrame:(current application's NSMakeRect(0, rowTop + 10, 390, 16))
		rowBar's setIndeterminate:false
		rowBar's setMinValue:0
		rowBar's setMaxValue:100
		rowBar's setDoubleValue:0
		ordersContainer's addSubview:rowBar
		set end of orderBars to rowBar

		set rowStatus to my makeLabel("queued…", 400, rowTop + 10, 120, 16, false)
		ordersContainer's addSubview:rowStatus
		set end of orderStatusLabels to rowStatus

		set cmd to "nohup /bin/bash " & quoted form of my scriptPath() & " " & quoted form of u & " " & quoted form of destPath & " > " & quoted form of lp & " 2>&1 < /dev/null & echo $!"
		do shell script cmd
	end repeat

	my showStep(3)

	set pollTimer to current application's NSTimer's scheduledTimerWithTimeInterval:0.5 target:me selector:"pollProgress:" userInfo:(missing value) repeats:true
end step2Start:

on pollProgress:sender
	set totalAll to 0
	set doneAll to 0
	set allDone to true

	set n to count of logPaths
	repeat with i from 1 to n
		if (item i of orderFinished) is false then
			set allDone to false
			set lp to item i of logPaths
			set logText to my readFile(lp)
			if logText is not "" then
				set finalLine to my lastLineStartingWith(logText, "FINAL ")
				set errorLine to my lastLineStartingWith(logText, "ERROR ")
				set stateLine to my lastLineStartingWith(logText, "STATE ")

				set theBar to item i of orderBars
				set theStatus to item i of orderStatusLabels

				if finalLine is not "" then
					set dN to my valueFor(finalLine, "done")
					set tN to my valueFor(finalLine, "total")
					set item i of orderDone to dN
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
					set aN to my valueFor(stateLine, "active")
					set item i of orderTotals to tN
					set item i of orderDone to dN
					if tN > 0 then
						set pct to (dN / tN) * 100
						theBar's setDoubleValue:pct
					end if
					if aN > 0 then
						theStatus's setStringValue:((dN as text) & "/" & (tN as text) & " • " & (aN as text) & " active")
					else
						theStatus's setStringValue:((dN as text) & "/" & (tN as text))
					end if
				end if
			end if
		end if
	end repeat

	set totalAll to 0
	set doneAll to 0
	repeat with i from 1 to n
		set totalAll to totalAll + (item i of orderTotals)
		set doneAll to doneAll + (item i of orderDone)
	end repeat

	if totalAll > 0 then
		set overallPct to (doneAll / totalAll) * 100
		overallBar's setDoubleValue:overallPct
		set pctInt to round overallPct
		overallLabel's setStringValue:("Overall Progress: " & pctInt & "%  (" & doneAll & " of " & totalAll & ")")
	end if

	if allDone then
		pollTimer's invalidate()
		summaryLabel's setStringValue:("Downloaded " & doneAll & " of " & totalAll & " videos." & return & "Saved to: " & destPath)
		summaryLabel's setHidden:false
		closeButton's setHidden:false
	end if
end pollProgress:

on closeClicked:sender
	current application's NSApplication's sharedApplication()'s terminate:me
end closeClicked:

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
		set theResponse to missing value
		set theErr to missing value
		set theData to current application's NSURLConnection's sendSynchronousRequest:theRequest returningResponse:(reference to theResponse) |error|:(reference to theErr)
		if theData is missing value then return

		set jsonStr to (current application's NSString's alloc()'s initWithData:theData encoding:(current application's NSUTF8StringEncoding)) as text
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

on scriptPath()
	return (POSIX path of (path to me)) & "Contents/Resources/download_windobona.sh"
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
