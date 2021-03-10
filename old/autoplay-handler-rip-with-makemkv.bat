@echo off

rem This script is the wrapper to be invoked by windows autoplay. You can configure a new handler
rem using Default Programs Editor.

rem Simple workaround for the powershell execution policy stuff.
cat d:\ripping\test.ps1 | powershell -

echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo " *************************************************************************** "
echo " *************************************************************************** "
echo " **                                                                       ** "
echo " **           ALL DONE RIPPING! PRESS [ENTER] TO CLOSE THIS               ** "
echo " **                      AND INSERT THE NEXT DISK!                        ** "
echo " **                                                                       ** "
echo " *************************************************************************** "
echo " *************************************************************************** "

pause
