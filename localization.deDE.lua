if( GetLocale() ~= "deDE" ) then
	return;
end

ActionBarSaverLocals = setmetatable( {
}, { __index = ActionBarSaverLocals } );