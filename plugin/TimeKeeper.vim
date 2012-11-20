" vim: ts=4 tw=4 fdm=marker :
" ---------------------------------------------------------------------------------
"     file: TimeKeeper
"     desc: This plugin will keep track of the time spent in the editor. Will
"           try and workout how much time is being spent on the current activity.
"           It will allocate the time that is spent on the current task.
"
"           The timekeeping is organised by jobs and the jobs are grouped in the
"           projects.
"			
"			The timesheet data is stored in a comma separated format, so that
"           it is easy to use and import into different tools. It will stored
"           by default in the $(HOME)/timesheet.tmk
"
"   author: Peter Antoine
"     date: 16/11/2012 18:05:21
" ---------------------------------------------------------------------------------
"                      Copyright (c) 2012 Peter Antoine
"                             All rights Reserved.
"                     Released Under the Artistic Licence
" ---------------------------------------------------------------------------------
"
" This plugin has a global dictionary so the plugin should only be loaded ones.
"
if g:developing || !exists("s:TimeKeeperPlugin")
" Script Initialisation block												{{{
	let s:TimeKeeperPlugin = 1

	" global settings
	if !exists("g:TimeKeeperAwayTime")
		let g:TimeKeeperAwayTime = 360    				" 5ive minutes and then assume that the time was not working time.
	endif

	if !exists("g:TimeKeeperDefaultProject")
		let g:TimeKeeperDefaultProject = 'default'		" the name of the default/current project
	endif

	if !exists("g:TimeKeeperDefaultJob")
		let g:TimeKeeperDefaultJob = 'default'			" the name of the default/current job
	endif

	if !exists("g:TimeKeeperUseGitProjectBranch")
		let g:TimeKeeperUseGitProjectBranch = 1			" use the Git repository as the project name, and the branch as the job
	endif

	if !exists("g:TimeKeeperUpdateFileTime")
		let g:TimeKeeperUpdateFileTime = 60 * 15		" time before the timesheet is written to the file
	endif

	if !exists("g:TimeKeeperUseLocal")
		let g:TimeKeeperUseLocal = 0					" Use the file local to where the browser was started or use the user default
	endif

	if !exists("g:TimeKeeperFileName")					" What file should the TimeKeeper store the timesheet in
		if (g:TimeKeeperUseLocal)
			let g:TimeKeeperFileName = 'timekeeper.tmk'
		else
			let g:TimeKeeperFileName = $HOME . '/' . '.timekeeper.tmk'
		endif
	endif

	if !exists("g:TimeKeeperUseGitNotes")				" If vim is in a git repository add git notes with the time periodically
		let g:TimeKeeperUseGitNotes = 1
	endif

	if !exists("g:TimeKeeperGitNoteUpdateTime")
		let g:TimeKeeperGitNoteUpdateTime = 60 * 60		" Update the git not once an hour - This will only be updated when the timesheet is updates.
	endif

	" internal data structures for holding the projects
	let s:current_job = g:TimeKeeperDefaultJob
	let s:project_list = {}

	" script level functions to start time capture
	let s:list_time_called = 0
	let s:user_stopped_typing = 0
	let s:user_started_typing = localtime()
	let s:last_update_time = localtime()

	" needed to hold the start dir so the :cd changes can be detected
	let s:current_dir = getcwd()

	augroup TimeKeeper						" Create the group to hold all the events.
"																			}}}
" PUBLIC FUNCTIONS
" FUNCTION: TimeKeeper_StopTracking() 						 				{{{
"  
" This function will stop the TimeKeeper tracking the users time.
"
" vars:
"      none.
" returns:
"      nothing.
"
function! TimeKeeper_StopTracking()
	au! TimeKeeper
	call s:TimeKeeper_UpdateJob(s:current_project,s:current_job,(s:user_stopped_typing - s:user_started_typing))
	call TimeKeeper_SaveTimeSheet(0)
endfunction
"																			}}}
" FUNCTION: TimeKeeper_StartTracking()  									{{{
"  
" This function will start the TimeKeeper tracking the users time.
"
" vars:
"      none.
" returns:
"      nothing.
"
function! TimeKeeper_StartTracking()
	call s:TimeKeeper_LoadTimeSheet()

	if g:TimeKeeperUseGitProjectBranch
		call s:TimeKeeper_SetJobNameFromGitRepository()
	endif

	if s:current_project == ''
		let s:current_project = g:TimeKeeperDefaultProject
	endif

	if s:current_job == ''
		let s:current_job = g:TimeKeeperDefaultJob
	endif

	call s:TimeKeeper_AddJob(s:current_project,s:current_job)

	au TimeKeeper CursorHoldI * nested call s:TimeKeeper_UserStoppedTyping()
	au TimeKeeper CursorHold  * nested call s:TimeKeeper_UserStoppedTyping()
	au TimeKeeper FocusLost   * nested call s:TimeKeeper_UserStoppedTyping()
	au TimeKeeper VimLeave    * nested call s:TimeKeeper_StopTracking()

	if g:TimeKeeperUseGitProjectBranch
		au TimeKeeper CmdwinLeave : call s:TimeKeeper_CheckForCWDChange()
	endif
endfunction
"																			}}}
" FUNCTION: TimeKeeper_GetCurrentJobString() 								{{{
"  
" This function will return the current job string and the time that the current
" job has taken so far.
"
" vars:
"      none.
" returns:
"      string = "<project>.<job>#dd:hh:mm"
"
function! TimeKeeper_GetCurrentJobString()
	
	let el_time_mins  = (s:project_list[s:current_project].job[s:current_job].total_time / 60) % 60
	let el_time_hours = (s:project_list[s:current_project].job[s:current_job].total_time / (60*60)) % 60
	let el_time_days  = (s:project_list[s:current_project].job[s:current_job].total_time / (60*60*24))
	
	return s:current_project . '.' . s:current_job . '#' . el_time_days . ':' . el_time_hours . ':' . el_time_mins

endfunction
"																			}}}
" FUNCTION: TimeKeeper_SaveTimeSheet(timesheet_file)  						{{{
"
" This function will save the timesheet to the given file.
"
" The format of the time sheet is a basic comma separated file that has the following
" format:
" 
"      project, job, start_time, total_time
"
" Not all times are seconds from the start of the unix epoc.
"
" vars:
"	timesheet	The file to open as a timesheet
"
" returns:
"	1 - If the database could be loaded.
"	0 - If the database failed to load.
"
function! TimeKeeper_SaveTimeSheet(create)
	let result = 0

	if !a:create && !filewritable(g:TimeKeeperFileName)
		echomsg "timesheet file is not writable"
	else
		echomsg "in the write"
		let output = []

		" Ok, lets build the output List of lists that need to be written to the file.
		for project_name in keys(s:project_list)
			echomsg "project " . project_name

			for job_name in keys(s:project_list[project_name].job)
				let line = project_name . ',' . job_name . ',' . 
					\ s:project_list[project_name].job[job_name].start_time . ',' . s:project_list[project_name].job[job_name].total_time
				call add(output,line)
			endfor
		endfor
		
		" write the result to a file
		call writefile(output,g:TimeKeeperFileName)

		let s:last_update_time = localtime()
	endif
endfunction
"																			}}}
" INTERNAL FUNCTIONS
" FUNCTION: s:TimeKeeper_UpdateGitNote()									{{{
" 
" This function will read in the git note from the current branch and then
" find the line that matches the current job in the note and then write the
" note back. This will use a temporary file that is used to do the write back
" a this is the only sane way to get a multilined note back in to git. 
"
" This code forces the add so that it will create/update the note. As the 
" order of the lines in the note are preserved and only the current job is
" updated (for the current user) the note should not clash when merged/pushed
" but we will have to see how well this works in the real world.
"
" vars:
"	none
"
" returns:
"	nothing.
"
" TODO: testing removed the s:
function! TimeKeeper_UpdateGitNote()
	redir => git_note_contents
	silent execute "!git notes --ref=timekeeper show"
	redir END
	
	" git quire nicely adds x00 for some reason to outputs - and remove the command line
	let time_notes = split(substitute(git_note_contents,'[\x00]',"","g"),"\x0d")
	call remove(time_notes,0)
	
	"lets get the users email address - leaving the x00 on the end, we can use this as a delimiter
	let email_address = system("git config --get user.email")
	echomsg "email " . email_address

	" check to see if "error:" starts the string as denotes that there is not a note
	if (strpart(time_notes[0],0,6) == "error:")
		let time_notes = []
		let note_index = 0
		let time_notes = [ email_address . TimeKeeper_GetCurrentJobString() ]
		echomsg "time note " . time_notes[0]

	else
		" Ok, had a note, now find the required name in it
		name_length = strlen(email_address)

		while index < len(time_notes)
			if strpart(time_notes[index],0,name_length) == email_address
				time_notes[index] = email_address . TimeKeeper_GetCurrentJobString()
				echomsg "time note [index]" . time_notes[index]
				break
			endif
		endwhile

		" extend the list if it was not found in the note
		if (index == len(time_notes))
			call add(time_notes,email_address . TimeKeeper_GetCurrentJobString())
		endif
	endif

	" Ok, now write the updated note back to the repository - only use one temp file
	" don't want to DoS myself by using up all the disk with temp files.
	if !exists("s:gitnote_temp_file") || empty(s:gitnote_temp_file)
		let s:gitnote_temp_file = tempname()
	endif

	call writefile(time_notes,s:gitnote_temp_file)
	silent execute "!git notes --ref=timekeeper add -F " . s:gitnote_temp_file
endfunction
"																			}}}
" FUNCTION: s:TimeKeeper_SetJobNameFromGitRepository()						{{{
"
" This function will search the tree UPWARDS to find the git repository that the 
" file belongs to. If it cannot find the repository then it will generate an error
" and then return an empty string.
"
" vars:
"	none
"
" returns:
"	If there is a .git directory in the tree, it returns the directory that the .git
"	repository is in, else it returns the empty string.
"
function! s:TimeKeeper_SetJobNameFromGitRepository()
	let root = finddir(".git",expand('%:h'). "," . expand('%:p:h') . ";" . $HOME)
	
	" get the name of the directory will use as the project name
	let s:current_project = substitute(fnamemodify(root,':p:h:h'),fnamemodify(root,':p:h:h:h') . '/','','')
	
    let branch = system("git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* //'")

	if branch != ''
        let s:current_job = substitute(branch, '\n', '', 'g')
	else
	    let s:current_job = ''
	endif
endfunction
"																			}}}
" FUNCTION: s:TimeKeeper_UpdateJob(project_name,job_name,time)				{{{
"
" This function will update a job with the time that has elapsed.
" 
" vars:
"	project_name	The name of the project.
"	job_name		The name of the job.
"	time			The name of the time.
"
" returns:
"	nothing
"
function! s:TimeKeeper_UpdateJob(project_name, job_name, time)
	let job = s:TimeKeeper_AddJob(a:project_name,a:job_name)
	
	let job.total_time += a:time
	let s:project_list[a:project_name].total_time += a:time

endfunction
"																			}}}
" FUNCTION: s:TimeKeeper_RequestCreate()  									{{{
"
" This function will ask the user before creating the timesheet file.
" 
" vars:
"	timesheet	The file to open as a timesheet
" returns:
"	nothing
"
function! s:TimeKeeper_RequestCreate()
	
	let g:TimeKeeperFileName = input("Please supply TimeKeeper timesheet filename: ",g:TimeKeeperFileName)

	if ( g:TimeKeeperFileName != '' )
		" create the default job
		call s:TimeKeeper_AddJob(s:current_project,s:current_job)
		call TimeKeeper_SaveTimeSheet(1)
	endif

endfunction
"																			}}}
" FUNCTION: s:TimeKeeper_ImportJob(values)  								{{{
"
" This function will import a job into the timesheet dictionary.
" 
" format:
" 
"      values = [project, job, start_time, total_time]
"
" Not all times are seconds from the start of the unix epoc.
"
" vars:
"	timesheet	The file to open as a timesheet
" returns:
"	nothing
"
function! s:TimeKeeper_ImportJob(values)

	if len(a:values) == 4
		" set the job values
		let job = s:TimeKeeper_AddJob(a:values[0],a:values[1])
		let job.start_time = a:values[2]
		let job.total_time = a:values[3]

		"set the project totals
		let s:project_list[a:values[0]].total_time	+= a:values[3]
		let s:project_list[a:values[0]].num_jobs	+= 1
	endif
endfunction
"																			}}}
" FUNCTION: s:TimeKeeper_LoadTimeSheet()  							{{{
"
" This function will load the timesheet that is given. If the timesheet file given
" does not exist it will return an error.
"
" The format of the time sheet is a basic comma separated file that has the following
" format:
" 
"      project, job, start_time, total_time
"
" Not all times are seconds from the start of the unix epoc.
"
" vars:
"	none
"
" returns:
"	1 - If the database could be loaded.
"	0 - If the database failed to load.
"
function! s:TimeKeeper_LoadTimeSheet()
	let result = 0
	
	" If the file does not exist
	if empty(glob(g:TimeKeeperFileName))
		call s:TimeKeeper_RequestCreate()
	else
		
		if !filewritable(g:TimeKeeperFileName)
			echomsg "Timesheet file cannot be written"
		
		elseif !filereadable(g:TimeKeeperFileName)
			echomsg "Timesheet file cannot be read"

		else
			let timesheet_data = readfile(g:TimeKeeperFileName)
			
			if empty(timesheet_data)
				echomsg "timesheet file empty"
			else
				let result = 1

				for item in timesheet_data
					let values = split(item,',',1)

					"Should now have a list of the items in the line
					call s:TimeKeeper_ImportJob(values)
				endfor

				let s:user_last_update_time = localtime()
			endif
		endif
	endif

	return result
endfunction
"																			}}}
" FUNCTION: s:TimeKeeper_AddJob(project_name,job_name)  						{{{
"
" This function will add a job to the project/job database. If the project
" does not exist it will be created, and if the job does not exist that will
" also be created as well.
"
" vars:
"	project_name	The project that the job should be created in.
" 	job_name		This is the job to create.
"
function! s:TimeKeeper_AddJob(project_name,job_name)
	" check to see if it is a new project
	if !has_key(s:project_list,a:project_name)
		let s:project_list[a:project_name] = {'total_time':0, 'num_jobs': 1, 'job': {} }
	endif

	" check to see if it is a new job that we are dealing with
	if !has_key(s:project_list[a:project_name].job,a:job_name)

		let s:project_list[a:project_name].job[a:job_name] = {'total_time':0, 'start_time': localtime() }
	endif

	return s:project_list[a:project_name].job[a:job_name]
endfunction
"																			}}}
" AUTOCMD FUNCTIONS
" FUNCTION: s:TimeKeeper_UserStartedTyping()									{{{
"
" This function will be called when the user has started typing again. This
" function will be called when the user moves the cursor or the editor regains
" keyboard focus.
"
" vars:
"	none
"
function! s:TimeKeeper_UserStartedTyping()
	" Do we throw away the time that the user has been away?
	if (localtime() - s:user_stopped_typing) < g:TimeKeeperAwayTime
		" No, add the elapsed time.
		call s:TimeKeeper_UpdateJob(s:current_project,s:current_job,(localtime() - s:user_started_typing))
	endif

	" check to see if we need to update the timesheet file
	if (s:last_update_time + g:TimeKeeperUpdateFileTime) < localtime()
		" Ok. we have to update the file now.
		call TimeKeeper_SaveTimeSheet(0)
	endif

	" update the started typing time
	let s:user_started_typing = localtime()
	let s:user_stopped_typing = localtime()

	" remove the events as these slow down the editor
	au! TimeKeeper CursorMovedI
	au! TimeKeeper CursorMoved
	au! TimeKeeper FocusGained
endfunction
"																			}}}
" FUNCTION: s:TimeKeeper_UserStoppedTyping()									{{{
"
" This function will be called when the user has stopped typing for the time
" that is specified in the updatetime system variable.
"
" vars:
"	none
"
function! s:TimeKeeper_UserStoppedTyping()
	let s:user_stopped_typing = localtime()

	" check to see if we need to update the timesheet file
	if (s:last_update_time + g:TimeKeeperUpdateFileTime) < s:user_stopped_typing
		" Ok. we have to update the file now.
		call TimeKeeper_SaveTimeSheet(0)
	endif

	" we need to wait for the Cursor to move as this is the user doing work again.
	au TimeKeeper CursorMovedI * nested call s:TimeKeeper_UserStartedTyping()
	au TimeKeeper CursorMoved  * nested call s:TimeKeeper_UserStartedTyping()
	au TimeKeeper FocusGained  * nested call s:TimeKeeper_UserStartedTyping()
	  
endfunction
"																			}}}
" FUNCTION: s:TimeKeeper_CheckForCWDChange()								{{{
"
" This function will check that after the user has exited the ':' command if
" the current directory has changed. If so if it is set to use local timesheets
" rather than global ones, it will check to see if the timesheet will have
" changed and will have to reload.
"
" vars:
"	none
"
function! s:TimeKeeper_CheckForCWDChange()
	" has the directory changed? 	
	if g:TimeKeeperUseLocal && s:current_dir != getcwd()
		call s:TimeKeeper_SaveTimeSheet(0)
		call s:TimeKeeper_LoadTimeSheet()
	endif

endfunction
"																			}}}
endif
