# TimeKeeper #

Version 3.0.0

A timekeeper plugin for vim to track you using automatically.

## Introduction ##

This is a git plugin that will track the time you spend working on a project.

This plugin will keep track of the time spent in the editor. Will
try and workout how much time is being spent on the current activity,
and it will track this data by project and the specific job within that project.

The times that are collected from the editor are stored in a simple comma separated timesheet.
This should make it easy to use and import into different tools. It will stored
by default in the $(HOME)/timesheet.tmk. This is obviously configurable.

This plugin will also allow for the timesheet data to be added as a
git note. This will allow for the time to be read by software that
can read the contents of these notes.

The git notes are only added to the current branch for the current 
job, hopefully this will reduce the problems that git-notes have with
push/branching and merging.

The plugin will find other instances of vim with the plugin loaded, and the first one to load
will become the master server. All other instances will send there updates to the server. If the
current server disappears then the first to notice will become the new server. This will reduce
the chance of two instances losing time updates from other servers.

If you set up the git hooks that are provided, the timekeeper will also amend you commits to
allow for the timetracking information to be added to the end of your commits. This is in the
format that Redmine time tracking can read.

## Installation ##

Simply copy the contents of the plugin directory to the plugin directory in your git installation.

You can leave the configuration variables alone as these have sensible defaults and if you
put the following line in your .vimrc the timekeeper will start when you start typing:

    call TimeKeeper_StartTracking()

It would be a good idea to map the to toggle function to a key, i.e.:

	:map <silent> <F8> :call TimeKeeper_ToggleTaskWindow()<cr>

And the should be it. Once you have done that once then you can set g:TimeKeeperStartOnLoad to
1 and then TimeKeeper will start every time vim loads.

If you plan to use project local tracking, the setting the following option in your vimrc would
be a good plan:
	
	:set g:TimeKeeperUseFlatFile = 0

This will use a directory structure for the timekeeper files for user/machines to allow for the
timekeeper files to avoid merges when committed to an SCM. Also, some of the following goodness
is going to be only available to directory file users.

If you are using directory files, as I would recommend, then when moving into a new directory it
does not request that the timesheet is created automatically. But, you can simply call:

	:call TimeKeeper_CreateTimesheet()

The will create the timesheet in the local directory.

## Important Changes ##

- File Format
An option has been added to use a directory structure for the users tracking files. This file is
designed not to clash with the other users so that it avoids merge conflicts. This does mean that
the flat file will have to be converted to the new format. You will need to run the conversion
script for that. This option should only be used if you are intending to use local trackers. It will
work for global tracking but is of no real use.

If you want to use the new format (on *nix) you can run the script script/convert_to_dir.sh in the
script directory in every project that you use it in, and then set the flag.

## Git Hooks ##

To set up the Git hooks you will need to do the following in the root directory of the git repository.

    ln -s ~/.vim/githooks/prepare-commit-msg .git/hooks/prepare-commit-msg
    ln -s ~/.vim/githooks/post-commit .git/hooks/post-commit

On Windows (not tested) you will need to copy them into hooks directory.

The above assumes you have these plugins installed locally, else you will need to amend the source of
the plugin, also it assumes that you don't already have these hooks, if you do then you will need
to integrate these with your current hooks. I assume just adding:

   .sh ~/.vim/githooks/prepare-commit-msg $1 $2 $3 

to the end of your current prepare-commit-msg (and do similar for post) will do the job you need.

## TODO ##

1. Sharing/concatenating times.
    As I work on more than one machine it would be nice to be able to collect the total time from
    all machines. This should be doable for user and jobs. As the sharing is being done via Git
	the changes should have been committed, so the times would have been committed to the repo
	before the sharing, only the total need to be collected.

2. Shared Notes.
    This is more complicated, as some notes might want to be kept private. So the notes should be
	able to be encrypted. Sadly the blowfish and zip crypto functions are not exposed a vimscript
	functions, so can''t be used. There is a blowfish.vim plugin that Yukihiro Nakadaira has
	written in pure vimscript, which might be the correct solution or a least nick his
	implementations of the bitwise functions and then write and use xxtea - which should be a
	bit quicker (but this is vimscript - so speed might not be a issue). Initially I might rot13
	all messages, as this will at least hide from casual view the other notes.

	This is now fixable, now having the directory structure for timesheets, a general timesheet
	can be created as all "ALL_CAPITALS" jobs placed into there and viewable to all users.

3. Auto Jobbing.
	I write code, bad code which never gets finished and is normally loaded with TODO, FIXME
	and the glorious HACK. These need to be auto added as jobs in the job list. Need to work
	out when the files need to be scanned as to not cause problems with typing and causing 
	un-expected pauses in the editor. Could be a problem with some of the bigger files that
	I have to work with.
    
	With the directory structure and the shared notes file, the auto-jobbing can be added to this
	file. If it uses the tags a specified above, these can be germinate jobs that always exist
	and all the jobs added to this.

4. Session Length.
	It would be really nice to know how much time I was actually adding to the project in this
	typing session. So would need to check for session breaks, periods of non-typing by clock
	time that is greater than an explicit length, and track that. Also be able to track time
	by the length of the session. I.e. total length of the working day, excluding breaks. Also
	for simple how well/efficiently I am working how much of my day was actually spent at the
	keyboard. (obviously adding design, testing and other non-keyboard working times will have to
	be handled.)

## Extra Contributor(s) ##

	GitHub User: mhhf - Bug fixes for version 2.0.1

## Licence and Copyright ##
                    Copyright (c) 2012 - 2013 Peter Antoine
                             All rights Reserved.
                     Released Under the Artistic Licence
