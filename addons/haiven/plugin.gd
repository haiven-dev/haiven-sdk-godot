# The editor plugin entry point.
#
# Deliberately empty of editor behaviour. `plugin.cfg` is what makes this
# installable through the Plugins tab and what a project enables, but the SDK
# itself is plain script that a game loads directly — an addon that only works
# once someone has ticked a checkbox in the editor would be a worse SDK than one
# that does not.
@tool
extends EditorPlugin
