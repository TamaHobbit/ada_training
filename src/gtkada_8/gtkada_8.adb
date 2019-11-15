-- This is a simple ada program, that demonstrates gtkada
-- It draws a window with some elements in it.

with gtk.main;
with gtk.window; 			use gtk.window;
with gtk.widget;  			use gtk.widget;
with gtk.box;				use gtk.box;
with gtk.button;     		use gtk.button;
with gtk.toolbar; 			use gtk.toolbar;
with gtk.tool_button;		use gtk.tool_button;
with gtk.enums;				use gtk.enums;
with gtk.gentry;			use gtk.gentry;
with gtk.combo_box_text;	use gtk.combo_box_text;

with glib.object;			use glib.object;

with ada.text_io;			use ada.text_io;

with callbacks_3;

procedure gtkada_8 is

	window 					: gtk_window;
	box_back				: gtk_box;
	box_left, box_right		: gtk_box;
	box_console				: gtk_box;
	box_drawing				: gtk_box;
	button_up, button_down	: gtk_tool_button;	
	toolbar					: gtk_toolbar;
	console					: gtk_entry;
	console_2    			: gtk_combo_box_text;	
begin
	gtk.main.init;

	gtk_new (window);
	window.set_title ("Some Title");
	window.set_default_size (800, 600);

	-- background box
	gtk_new_hbox (box_back);
	set_spacing (box_back, 10);
	add (window, box_back);

	-- left box
	gtk_new_hbox (box_left);
	set_spacing (box_left, 10);
	add (box_back, box_left);

	-- right box
	gtk_new_vbox (box_right);
	set_spacing (box_right, 10);
	add (box_back, box_right);

	-- toolbar on the left
	gtk_new (toolbar);
	set_orientation (toolbar, orientation_vertical);
	pack_start (box_left, toolbar);
	
	-- Create a button and place it in the toolbar:
	gtk.tool_button.gtk_new (button_up, label => "UP");
	insert (toolbar, button_up);
	button_up.on_clicked (callbacks_3.write_message_up'access, toolbar);

	-- Create another button and place it in the toolbar:
	gtk.tool_button.gtk_new (button_down, label => "DOWN");
	insert (toolbar, button_down);
	button_down.on_clicked (callbacks_3.write_message_down'access, toolbar);


	-- console on the right top
	gtk_new_vbox (box_console);
	set_spacing (box_console, 10);
	add (box_right, box_console);

	-- a simple text entry
	gtk_new (console);
	set_text (console, "cmd");
	add (box_console, console);
	console.on_activate (callbacks_3.echo_command_simple'access); -- on hitting enter

	-- a more advanced text entry below
	-- gtk_new_with_entry (console_2);
	-- 	set_text (console_2, "cmd");
	-- console_2.append_text ("cmd1");
	-- console_2.append_text ("cmd2 cmd2");	
	-- add (box_console, console_2);
	-- console_2.on_changed (callbacks_3.echo_command_advanced'access);

	
	-- drawing area on the right bottom
	gtk_new_hbox (box_drawing);
	set_spacing (box_drawing, 10);
	add (box_right, box_drawing);


	
	window.on_destroy (callbacks_3.terminate_main'access);
	
	window.show_all;

	gtk.main.main;

end;
