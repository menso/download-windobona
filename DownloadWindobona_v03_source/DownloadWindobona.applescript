on run
	set urlList to {}
	repeat
		set promptText to "Windobona media page URL #" & ((count of urlList) + 1) & ":" & return & "Click Add to queue another URL, or Done to start downloading."
		try
			set theDialog to display dialog promptText default answer "" with title "DownloadWindobona" buttons {"Cancel", "Done", "Add"} default button "Add"
		on error number -128
			return
		end try
		set enteredURL to text returned of theDialog
		set btn to button returned of theDialog

		if enteredURL is not "" then
			set end of urlList to enteredURL
		end if

		if btn is "Done" then exit repeat
	end repeat

	if (count of urlList) is 0 then
		display alert "No URL entered" message "Please run the app again and paste at least one Windobona URL." as warning
		return
	end if

	try
		set destFolder to choose folder with prompt "Choose a destination folder for the downloaded videos:"
	on error number -128
		return
	end try
	set destPath to POSIX path of destFolder

	set scriptPath to (POSIX path of (path to me)) & "Contents/Resources/download_windobona.sh"
	set stamp to do shell script "date +%s"
	set orderCount to count of urlList

	-- launch one detached background downloader per order, so every order gets
	-- its own concurrent download slot instead of queuing behind the others
	set logPaths to {}
	repeat with i from 1 to orderCount
		set u to item i of urlList
		set logPath to "/tmp/downloadwindobona_" & stamp & "_" & i & ".log"
		set end of logPaths to logPath
		do shell script "nohup /bin/bash " & quoted form of scriptPath & " " & quoted form of u & " " & quoted form of destPath & " > " & quoted form of logPath & " 2>&1 < /dev/null & echo $!"
	end repeat

	set orderTotal to {}
	set orderDone to {}
	set orderActive to {}
	set orderSkipped to {}
	set orderFailed to {}
	set orderFinished to {}
	repeat with i from 1 to orderCount
		set end of orderTotal to 0
		set end of orderDone to 0
		set end of orderActive to 0
		set end of orderSkipped to 0
		set end of orderFailed to "none"
		set end of orderFinished to false
	end repeat

	set errorMessages to {}

	-- effectively no ceiling: the previous 4-hour limit caused the app to
	-- report "Apple event timed out" even on batches that were, in fact,
	-- still downloading successfully in the background
	with timeout of 1000000000 seconds
		repeat
			delay 0.5
			set stillRunning to false

			repeat with i from 1 to orderCount
				if item i of orderFinished is false then
					set lp to item i of logPaths
					try
						set lastLines to do shell script "tail -n 8 " & quoted form of lp & " 2>/dev/null"
					on error
						set lastLines to ""
					end try

					set finalLine to my lastLineStartingWith(lastLines, "FINAL ")
					set errorLine to my lastLineStartingWith(lastLines, "ERROR ")
					set stateLine to my lastLineStartingWith(lastLines, "STATE ")

					if finalLine is not "" then
						set item i of orderDone to my valueFor(finalLine, "done")
						set item i of orderTotal to my valueFor(finalLine, "total")
						set item i of orderSkipped to my valueFor(finalLine, "skipped")
						set item i of orderFailed to my textValueFor(finalLine, "failed")
						set item i of orderActive to 0
						set item i of orderFinished to true
					else if errorLine is not "" then
						set end of errorMessages to ("Order " & i & ": " & errorLine)
						set item i of orderActive to 0
						set item i of orderFinished to true
					else if stateLine is not "" then
						set item i of orderTotal to my valueFor(stateLine, "total")
						set item i of orderDone to my valueFor(stateLine, "done")
						set item i of orderActive to my valueFor(stateLine, "active")
					end if

					if item i of orderFinished is false then set stillRunning to true
				end if
			end repeat

			set totalAll to 0
			set doneAll to 0
			set activeAll to 0
			set activeOrders to 0
			repeat with i from 1 to orderCount
				set totalAll to totalAll + (item i of orderTotal)
				set doneAll to doneAll + (item i of orderDone)
				set activeAll to activeAll + (item i of orderActive)
				if (item i of orderActive) > 0 then set activeOrders to activeOrders + 1
			end repeat

			if totalAll > 0 then
				set progress total steps to totalAll
				set progress completed steps to doneAll
				set overallPct to round (doneAll / totalAll * 100)
				set progress description to "Overall Download Progress: " & overallPct & "%  (" & doneAll & " of " & totalAll & ")"
				if activeAll > 0 then
					set progress additional description to activeOrders & " order(s) active — " & activeAll & " video(s) downloading at once"
				else
					set progress additional description to "Starting…"
				end if
			end if

			if not stillRunning then exit repeat
		end repeat
	end timeout

	set progress total steps to 0
	set progress completed steps to 0
	set progress description to ""
	set progress additional description to ""

	set totalAll to 0
	set doneAll to 0
	set skippedAll to 0
	set failedAll to {}
	repeat with i from 1 to orderCount
		set totalAll to totalAll + (item i of orderTotal)
		set doneAll to doneAll + (item i of orderDone)
		set skippedAll to skippedAll + (item i of orderSkipped)
		set thisFailed to item i of orderFailed
		if thisFailed is not "none" and thisFailed is not "" then
			set end of failedAll to thisFailed
		end if
	end repeat

	repeat with lp in logPaths
		do shell script "rm -f " & quoted form of lp
	end repeat

	set summary to "Downloaded " & doneAll & " of " & totalAll & " videos successfully."
	if skippedAll > 0 then
		set summary to summary & return & "Skipped " & skippedAll & " link(s) without a video in them."
	end if
	if (count of failedAll) > 0 then
		set summary to summary & return & "Failed after retries: " & (my joinList(failedAll, ", "))
	end if
	set summary to summary & return & return & "Saved to: " & destPath
	if (count of errorMessages) > 0 then
		set summary to summary & return & return & "Errors:" & return & (my joinList(errorMessages, return))
	end if

	display dialog summary buttons {"OK"} default button "OK" with title "DownloadWindobona"
end run

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
			set valueText to text ((length of searchKey) + 1) thru (length of t) of t
			return valueText as integer
		end if
	end repeat
	return 0
end valueFor

on textValueFor(lineText, key)
	if lineText is "" then return ""
	set searchKey to key & "="
	set AppleScript's text item delimiters to " "
	set toks to text items of lineText
	set AppleScript's text item delimiters to ""
	repeat with t in toks
		set t to t as string
		if t begins with searchKey then
			if (length of t) = (length of searchKey) then return ""
			return text ((length of searchKey) + 1) thru (length of t) of t
		end if
	end repeat
	return ""
end textValueFor

on joinList(theList, delim)
	set AppleScript's text item delimiters to delim
	set joined to theList as string
	set AppleScript's text item delimiters to ""
	return joined
end joinList
