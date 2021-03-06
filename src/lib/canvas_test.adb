------------------------------------------------------------------------------
--                  GtkAda - Test and Education Program                     --
--                                                                          --
--      Bases on the package gtkada.canvas_view written by                  --
--      E. Briot, J. Brobecker and A. Charlet, AdaCore                      --
--                                                                          --
--      Modified and simplyfied by Mario Blunk, Blunk electronic            --
--                                                                          --
-- This library is free software;  you can redistribute it and/or modify it --
-- under terms of the  GNU General Public License  as published by the Free --
-- Software  Foundation;  either version 3,  or (at your  option) any later --
-- version. This library is distributed in the hope that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE.                            --
--                                                                          --
-- You should have received a copy of the GNU General Public License and    --
-- a copy of the GCC Runtime Library Exception along with this program;     --
-- see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see    --
-- <http://www.gnu.org/licenses/>.                                          --
--                                                                          --
------------------------------------------------------------------------------

--   For correct displaying set tab width in your editor to 4.

--   The two letters "CS" indicate a "construction site" where things are not
--   finished yet or intended for the future.

--   Please send your questions and comments to:
--
--   info@blunk-electronic.de
--   or visit <http://www.blunk-electronic.de> for more contact data
--
--   history of changes:
--

-- Rationale: Aims to help users understanding programming with gtkada,
-- especially creating a canvas with items displayed on it.
-- The code is reduced to a minimum so that the newcomer is not overtaxed
-- and is concerned with only the most relevant code.

with ada.text_io;			use ada.text_io;

with interfaces.c.strings;	use interfaces.c.strings;

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
with gtk.frame;				use gtk.frame;
with gtk.handlers;			use gtk.handlers;
with gtk.scrolled_window;	use gtk.scrolled_window;
with gtk.adjustment;		use gtk.adjustment;
with gtk.bin;				use gtk.bin;
with gtk.scrollable;		use gtk.scrollable;
with gtk.style_context;		use gtk.style_context;

with glib.properties.creation;	use glib.properties.creation;

with cairo;					use cairo;

with gtkada.types;			use gtkada.types;
with gtkada.handlers;		use gtkada.handlers;
with gtkada.bindings;		use gtkada.bindings;

with gdk;					use gdk;
with gdk.window;			use gdk.window;
with gdk.window_attr;		use gdk.window_attr;
with gdk.event;				use gdk.event;
with gdk.rgba;

with gnat.strings;
with pango.layout;					use pango.layout;
-- with pango.font;					use pango.font;

with system.storage_elements;		use system.storage_elements;
with ada.unchecked_deallocation;
with ada.containers;				use ada.containers;
with ada.containers.doubly_linked_lists;

package body canvas_test is

	function to_string (d : in gdouble) return string is begin
		return gdouble'image (d);
	end;

	function to_string (d : in gint) return string is begin
		return gint'image (d);
	end;

	function to_string (p : in type_view_point) return string is begin
		return ("view x/y [pixels]" & to_string (gint (p.x)) & "/" & to_string (gint (p.y)));
	end;

	function to_string (d : in type_model_coordinate) return string is begin
		return type_model_coordinate'image (d);
	end;
	
	function to_string (p : in type_model_point) return string is begin
		return ("model x/y [mm]" & to_string (p.x) & "/" & to_string (p.y));
	end;

	
	model_signals : constant gtkada.types.chars_ptr_array := (
		1 => new_string (string (signal_layout_changed))
		);
	
	view_signals : constant gtkada.types.chars_ptr_array := (
		1 => new_string (string (signal_viewport_changed))
		);

	h_adj_property    : constant property_id := 1;
	v_adj_property    : constant property_id := 2;
	h_scroll_property : constant property_id := 3;
	v_scroll_property : constant property_id := 4;

	model_class_record : glib.object.ada_gobject_class := glib.object.uninitialized_class;
	view_class_record : aliased glib.object.ada_gobject_class := glib.object.uninitialized_class;
	
	function model_get_type return glib.gtype is begin
		glib.object.initialize_class_record (
			ancestor     => gtype_object,
			signals      => model_signals,
			class_record => model_class_record,
			type_name    => "gtkada_model",
			parameters   => (
				1 => (1 => gtype_none)  	-- layout_changed
				)
			);  
		return model_class_record.the_type;
	end model_get_type;
	
	procedure init (self : not null access type_model'class) is begin
		if not self.is_created then
			g_new (self, model_get_type);
		end if;
	end;
	
	procedure gtk_new (self : out type_model_ptr) is begin
		self := new type_model;
		init (self);
	end;	


-- CONVERSIONS BETWEEN COORDINATE SYSTEMS
	
	function view_to_model (
		self   : not null access type_view;
		p      : type_view_point) 
		return type_model_point is
	begin
		return (
			x	=> type_model_coordinate (p.x / self.scale) + self.topleft.x,
			y	=> type_model_coordinate (p.y / self.scale) + self.topleft.y
			);
	end view_to_model;
	
	function view_to_model (
		self   : not null access type_view;
		rect   : in type_view_rectangle) -- position and size are in pixels
		return type_model_rectangle is
	begin
		return (x      => type_model_coordinate (rect.x / self.scale) + self.topleft.x,
				y      => type_model_coordinate (rect.y / self.scale) + self.topleft.y,
				width  => type_model_coordinate (rect.width / self.scale),
				height => type_model_coordinate (rect.height / self.scale));
	end view_to_model;


	
	function model_to_view (
		self   : not null access type_view;
		p      : in type_model_point) 
		return type_view_point is
	begin
		return (
			x => type_view_coordinate (p.x - self.topleft.x) * self.scale,
			y => type_view_coordinate (p.y - self.topleft.y) * self.scale
			);
	end model_to_view;

	function model_to_view (
		self   : not null access type_view;
		rect   : in type_model_rectangle)
		return type_view_rectangle is
		result : type_view_rectangle;
	begin
		result := (
			x      => type_view_coordinate (rect.x - self.topleft.x) * self.scale,
			y      => type_view_coordinate (rect.y - self.topleft.y) * self.scale,
			width  => type_view_coordinate (rect.width) * self.scale,
			height => type_view_coordinate (rect.height) * self.scale
			);
		
		return result;
	end model_to_view;

	function item_to_model (
		item   : not null access type_item'class;
		rect   : type_item_rectangle) return type_model_rectangle
	is
		pos : type_model_point;
		result : type_model_rectangle := (rect.x, rect.y, rect.width, rect.height);
	begin
		pos := position (item);
		result.x := result.x + pos.x;
		result.y := result.y + pos.y;
			
		return result;
	end;

	function item_to_model (
		item	: not null access type_item'class;
		i_point	: type_item_point) return type_model_point
	is
		r : constant type_model_rectangle := item.item_to_model ((i_point.x, i_point.y, 0.0, 0.0));
	begin
		return (r.x, r.y);
	end;


	
	function get_scale (self : not null access type_view) return gdouble is
	begin
		return self.scale;
	end get_scale;
	
	procedure set_scale (
		self     : not null access type_view;
		scale    : gdouble := 1.0;
		preserve : type_model_point := no_point)
	is
		-- backup old scale
		old_scale : constant gdouble := self.scale;

		-- save requested scale
		new_scale : constant gdouble := scale;

		-- for calculating the new topleft point we need those tempoarily variables:
		cx, cy : type_model_coordinate;
		
		box : type_model_rectangle;
		p   : type_model_point;
	begin
		if preserve /= no_point then
			-- set p at the point given by preserve
			p := preserve;
		else
			-- get the visible area
			box := self.get_visible_area;

			-- set p at the center of the visible area
			p := (box.x + box.width / 2.0, box.y + box.height / 2.0);
		end if;

		self.scale := scale;

		-- Calculate the new topleft corner of the visible area.
		-- Reason: The next time a model point is computed (via view_to_model)
		-- the point must not change. So topleft is now moved so that
		-- function view_to_model returns for the same view point the same
		-- model point.
		cx := p.x - self.topleft.x;
		cx := cx * type_model_coordinate (old_scale);
		
		cy := p.y - self.topleft.y;
		cy := cy * type_model_coordinate (old_scale);
		
		self.topleft := (
			p.x - cx / type_model_coordinate (new_scale),
			p.y - cy / type_model_coordinate (new_scale)
			);
		
		self.scale_to_fit_requested := 0.0;
		self.set_adjustment_values;
		self.queue_draw;
	end set_scale;
	
	function get_visible_area (self : not null access type_view)
		return type_model_rectangle is
	begin
		return self.view_to_model (
			-- Assemble a type_view_rectangle which will be converted
			-- to a type_model_rectangle by function view_to_model.
			(
			-- The visible area of the view always starts at 0/0 (topleft corner):
			x		=> 0.0, 
			y		=> 0.0,

			-- The view size is adjusted by the operator. So it must be inquired
			-- by calling get_allocated_width and get_allocated_height.
			-- get_allocated_width and get_allocated_height return an integer type
			-- which corresponds to the number of pixels required by self in y and x
			-- direction. Since the model coordinates are gdouble (a float type),
			-- the number of pixels must be converted to a gdouble type:
			width	=> gdouble (self.get_allocated_width),
			height	=> gdouble (self.get_allocated_height)
			));
	end get_visible_area;

	procedure union (
		rect1 : in out type_model_rectangle;
		rect2 : type_model_rectangle) is
		right : constant type_model_coordinate := 
			type_model_coordinate'max (rect1.x + rect1.width, rect2.x + rect2.width);
		bottom : constant type_model_coordinate :=
			type_model_coordinate'max (rect1.y + rect1.height, rect2.y + rect2.height);
	begin
		rect1.x := type_model_coordinate'min (rect1.x, rect2.x);
		rect1.width := right - rect1.x;

		rect1.y := type_model_coordinate'min (rect1.y, rect2.y);
		rect1.height := bottom - rect1.y;
	end;

	function bounding_box (self : not null access type_item) return type_item_rectangle is
	begin
		--  assumes size_request has been called already
		return (0.0, 0.0, self.width, self.height);
	end;
	
	function model_bounding_box (self : not null access type_item'class) 
		return type_model_rectangle is
	begin
		return self.item_to_model (self.bounding_box);
	end;
	
	function bounding_box (
		self   : not null access type_model;
		margin : type_model_coordinate := 0.0)
		return type_model_rectangle is
		
		result : type_model_rectangle;
		is_first : boolean := true;

		procedure do_item (item : not null access type_item'class) is
			box : constant type_model_rectangle := item.model_bounding_box;
		begin
			if is_first then
				is_first := false;
				result := box;
			else
				union (result, box);
			end if;
		end do_item;
	begin
		type_model'class (self.all).for_each_item (do_item'access);

		if is_first then
			return no_rectangle;
		else
			result.x := result.x - margin;
			result.y := result.y - margin;
			result.width := result.width + 2.0 * margin;
			result.height := result.height + 2.0 * margin;
			return result;
		end if;
	end bounding_box;

	procedure viewport_changed (self : not null access type_view'class) is begin
		object_callback.emit_by_name (self, signal_viewport_changed);
	end viewport_changed;
	
	procedure set_adjustment_values (self : not null access type_view'class) is
		box   : type_model_rectangle;
		area  : constant type_model_rectangle := self.get_visible_area;
		min, max : gdouble;
	begin
		if self.model = null or else area.width <= 1.0 then
			--  not allocated yet
			return;
		end if;

		--  we want a small margin around the minimal box for the model, since it
		--  looks better.

		box := self.model.bounding_box (type_model_coordinate (view_margin / self.scale));

		--  we set the adjustments to include the model area, but also at least
		--  the current visible area (if we don't, then part of the display will
		--  not be properly refreshed).

		if self.hadj /= null then
			min := gdouble'min (gdouble (area.x), gdouble (box.x));
			max := gdouble'max (gdouble (area.x + area.width), gdouble (box.x + box.width));
			self.hadj.configure (
				value          => gdouble (area.x),
				lower          => min,
				upper          => max,
				step_increment => 5.0,
				page_increment => 100.0,
				page_size      => gdouble (area.width));
		end if;

		if self.vadj /= null then
			min := gdouble'min (gdouble (area.y), gdouble (box.y));
			max := gdouble'max (gdouble (area.y + area.height), gdouble (box.y + box.height));
			self.vadj.configure (
				value          => gdouble (area.y),
				lower          => min,
				upper          => max,
				step_increment => 5.0,
				page_increment => 100.0,
				page_size      => gdouble (area.height));
		end if;

		self.viewport_changed;
	end set_adjustment_values;

	procedure on_adj_value_changed (view : access glib.object.gobject_record'class) is
	-- Called when one of the scrollbars has changed value.		
		self : constant type_view_ptr := type_view_ptr (view);
		pos  : constant type_model_point := (
							x => type_model_coordinate (self.hadj.get_value),
							y => type_model_coordinate (self.vadj.get_value));
	begin
		if pos /= self.topleft then
			self.topleft := pos;
			self.viewport_changed;
			queue_draw (self);
		end if;
	end on_adj_value_changed;

	procedure view_set_property (
		object        : access glib.object.gobject_record'class;
		prop_id       : property_id;
		value         : glib.values.gvalue;
		property_spec : param_spec)
	is
		pragma unreferenced (property_spec);
		self : constant type_view_ptr := type_view_ptr (object);
	begin
		case prop_id is
			when h_adj_property =>
				self.hadj := gtk_adjustment (get_object (value));
				if self.hadj /= null then
					set_adjustment_values (self);
					self.hadj.on_value_changed (on_adj_value_changed'access, self);
					self.queue_draw;
				end if;

			when v_adj_property => 

				self.vadj := gtk_adjustment (get_object (value));

				if self.vadj /= null then
					set_adjustment_values (self);
					self.vadj.on_value_changed (on_adj_value_changed'access, self);
					self.queue_draw;
				end if;

			when h_scroll_property => null;

			when v_scroll_property => null;

			when others => null;
		end case;
	end view_set_property;
	
	procedure view_get_property (
		object        : access glib.object.gobject_record'class;
		prop_id       : property_id;
		value         : out glib.values.gvalue;
		property_spec : param_spec)
	is
		pragma unreferenced (property_spec);
		self : constant type_view_ptr := type_view_ptr (object);
	begin
		case prop_id is
			when h_adj_property => set_object (value, self.hadj);
			when v_adj_property => set_object (value, self.vadj);
			when h_scroll_property => set_enum (value, gtk_policy_type'pos (policy_automatic));
			when v_scroll_property => set_enum (value, gtk_policy_type'pos (policy_automatic));
			when others => null;
		end case;
	end view_get_property;

		function get_visibility_threshold (self : not null access type_item) return gdouble is
	begin
		return self.visibility_threshold;
	end get_visibility_threshold;
	
	function size_above_threshold (
		self : not null access type_item'class;
		view : access type_view'class) return boolean
	is
		r   : type_view_rectangle;
		threshold : constant gdouble := self.get_visibility_threshold;
	begin
		if threshold = gdouble'last then --  always hidden
			return false;
			
		elsif threshold > 0.0 and then view /= null then
			
			r := view.model_to_view (self.model_bounding_box);
			if r.width < threshold or else r.height < threshold then
				return false;
			end if;
			
		end if;
		return true;
	end size_above_threshold;

	procedure draw (
		self 	: not null access type_item;
		context	: type_draw_context) is 
	begin
-- 		put_line ("drawing ...");

		cairo.set_line_width (context.cr, 1.5);

		-- Draw objects with the corner points as specified in type_item (see spec for type_item):
		-- NOTE: The corner points are in item coordinates relative to the item position.
		-- See the calling procedure (translate_and_draw_item) for preparations.

		-- Point c10 (at 0/0) is the upper left point. All drawing starts from here downwards
		-- or to the right.
		
		-- draw the big X in red
		cairo.set_source_rgb (context.cr, gdouble (1), gdouble (0), gdouble (0)); -- red

		cairo.move_to (
			context.cr,
			type_view_coordinate (self.c10.x),
			type_view_coordinate (self.c10.y));
		
		cairo.line_to (
			context.cr,
			type_view_coordinate (self.c13.x),
			type_view_coordinate (self.c13.y));

		cairo.move_to (
			context.cr,
			type_view_coordinate (self.c12.x),
			type_view_coordinate (self.c12.y));
		
		cairo.line_to (
			context.cr,
			type_view_coordinate (self.c11.x),
			type_view_coordinate (self.c11.y));

		cairo.stroke (context.cr);

		
		-- draw the surounding rectangle in yellow
		cairo.set_source_rgb (context.cr, gdouble (1), gdouble (1), gdouble (0)); -- yellow
		
		cairo.rectangle (
			context.cr,
			type_view_coordinate (self.c10.x),
			type_view_coordinate (self.c10.y),
			type_view_coordinate (self.c13.x),
			type_view_coordinate (self.c13.y));

		cairo.stroke (context.cr);
		

		-- draw a line between point c1 and c2 in green
		cairo.set_source_rgb (context.cr, gdouble (0), gdouble (1), gdouble (0)); -- green
		
		cairo.move_to (
			context.cr,
			type_view_coordinate (self.c1.x),
			type_view_coordinate (self.c1.y));
		
		cairo.line_to (
			context.cr,
			type_view_coordinate (self.c2.x),
			type_view_coordinate (self.c2.y));
		
		cairo.stroke (context.cr);
	end;
	
	procedure translate_and_draw_item (
		self          : not null access type_item'class;
		context       : type_draw_context) is
	begin
		if not size_above_threshold (self, context.view) then
			return;
		end if;

		save (context.cr);

		-- Prepare the current transformation matrix (CTM) so that
		-- drawing the item specific things are drawn relative to the
		-- item position.
		translate (
			context.cr,
			type_view_coordinate (self.position.x),
			type_view_coordinate (self.position.y));

		-- draw the item
		self.draw (context);
		
		restore (context.cr);

	exception
		when e : others =>
			restore (context.cr);
			process_exception (e);
	end translate_and_draw_item;

	procedure set_transform (
		self	: not null access type_view;
		cr		: cairo.cairo_context;
		item	: access type_item'class := null)
	is
		model_p : type_model_point;
		view_p  : type_view_point;
	begin
		if item /= null then
			model_p := item.item_to_model (i_point => (0.0, 0.0));
		else
			model_p := (0.0, 0.0);
		end if;

		-- compute a view point according to current model point:
		view_p := self.model_to_view (model_p);

		-- Set the CTM so that following draw operations are relative
		-- to the current view point:
		translate (cr, view_p.x, view_p.y);

		-- Set the CTM so that following draw operations are scaled
		-- according to the scale factor of the view:
		scale (cr, self.scale, self.scale);

	end set_transform;
	
	procedure set_grid_size (
		self : not null access type_view'class;
		size : type_model_coordinate := 30.0) is
	begin
		self.grid_size := size;
	end set_grid_size;

	procedure draw_grid_dots (
		self    : not null access type_view'class;
		style   : gtkada.style.drawing_style;
		context : type_draw_context;
		area    : type_model_rectangle)
	is
		tmpx, tmpy  : type_view_coordinate;
	begin
		if style.get_fill /= null_pattern then
			set_source (context.cr, style.get_fill);
			paint (context.cr);
		end if;

		if self.grid_size /= 0.0 then
			new_path (context.cr);

			tmpx := type_view_coordinate (gint (area.x / self.grid_size)) * type_view_coordinate (self.grid_size);
			
			while tmpx < type_view_coordinate (area.x + area.width) loop
				tmpy := type_view_coordinate (gint (area.y / self.grid_size)) * type_view_coordinate (self.grid_size);
				
				while tmpy < type_view_coordinate (area.y + area.height) loop
					rectangle (context.cr, tmpx - 0.5, tmpy - 0.5, 1.0, 1.0);
					tmpy := tmpy + type_view_coordinate (self.grid_size);
				end loop;

				tmpx := tmpx + type_view_coordinate (self.grid_size);
			end loop;

			style.finish_path (context.cr);
		end if;
	end draw_grid_dots;
	
	procedure draw_internal (
		self    : not null access type_view;
		context : type_draw_context;
		area    : type_model_rectangle)
	is
		procedure draw_item (
			item : not null access type_item'class) is
		begin
			translate_and_draw_item (item, context);
		end;

		-- prepare draing style so that white grid dots will be drawn.
		style : drawing_style := gtk_new (stroke => gdk.rgba.white_rgba);
		
	begin
-- 		put_line ("draw internal ...");
		
		if self.model /= null then

			-- draw a black background:
			set_source_rgb (context.cr, 0.0, 0.0, 0.0);
			paint (context.cr);

			-- draw white grid dots:
			set_grid_size (self, 100.0);
			draw_grid_dots (self, style, context, area);
			
			self.model.for_each_item (draw_item'access, in_area => area);
			
		end if;
	end draw_internal;
	
	procedure refresh (
		self : not null access type_view'class;
		cr   : cairo.cairo_context;
		area : type_model_rectangle := no_rectangle)
	is
		a : type_model_rectangle;
		c : type_draw_context;
	begin
		if area = no_rectangle then
			a := self.get_visible_area;
		else
			a := area;
		end if;

		--  gdk already clears the exposed area to the background color, so
		--  we do not need to clear ourselves.

		c := (
			cr		=> cr,
			layout	=> self.layout,
			view	=> type_view_ptr (self));

		save (cr);
		self.set_transform (cr);
		self.draw_internal (c, a);
		restore (cr);
	end refresh;
	
	function on_view_draw (
		view	: system.address; 
		cr		: cairo_context) return gboolean;
	
	pragma convention (c, on_view_draw);
	--  default handler for "draw" on views.

	function on_view_draw (
		view	: system.address; 
		cr		: cairo_context) return gboolean is
		
		self : constant type_view_ptr := type_view_ptr (glib.object.convert (view));
		x1, y1, x2, y2 : gdouble;
	begin
		clip_extents (cr, x1, y1, x2, y2);

		if x2 < x1 or else y2 < y1 then
			refresh (self, cr);
		else
			refresh (self, cr, self.view_to_model ((x1, y1, x2 - x1, y2 - y1)));
		end if;

		return 1;

	exception
		when e : others =>
			process_exception (e);
			return 0;
	end on_view_draw;

	procedure on_view_realize (widget : system.address);
	pragma convention (c, on_view_realize);
	--  called when the view is realized
	
	procedure on_view_realize (widget : system.address) is
		w          : constant gtk_widget := gtk_widget (get_user_data_or_null (widget));
		allocation : gtk_allocation;
		window     : gdk_window;
		attr       : gdk.window_attr.gdk_window_attr;
		mask       : gdk_window_attributes_type;
	begin
		if not w.get_has_window then
			inherited_realize (view_class_record, w);
		else
			w.set_realized (true);
			w.get_allocation (allocation);

			gdk_new (
				attr,
				window_type => gdk.window.window_child,
				x           => allocation.x,
				y           => allocation.y,
				width       => allocation.width,
				height      => allocation.height,
				wclass      => gdk.window.input_output,
				visual      => w.get_visual,
				event_mask  => w.get_events or exposure_mask);
			
			mask := wa_x or wa_y or wa_visual;

			gdk_new (window, w.get_parent_window, attr, mask);
			register_window (w, window);
			w.set_window (window);
			get_style_context (w).set_background (window);

			--  see also handler for size_allocate, which moves the window to its
			--  proper location.
		end if;
	end on_view_realize;

	procedure on_size_allocate (view : system.address; alloc : gtk_allocation);
	pragma convention (c, on_size_allocate);
	--  default handler for "size_allocate" on views.
	
	procedure on_size_allocate (view : system.address; alloc : gtk_allocation) is
		self : constant type_view_ptr := type_view_ptr (glib.object.convert (view));
		salloc : gtk_allocation := alloc;
	begin
		--  for some reason, when we maximize the toplevel window in testgtk, or
		--  at least enlarge it horizontally, we are starting to see an alloc
		--  with x < 0 (likely related to the gtkpaned). the drawing area then
		--  moves the gdkwindow, which would introduce an extra ofset in the
		--  display (and influence the clipping done automatically by gtk+
		--  before it emits "draw"). so we prevent the automatic offseting done
		--  by gtkdrawingarea.

		salloc.x := 0;
		salloc.y := 0;
		self.set_allocation (salloc);
		set_adjustment_values (self);

		if self.get_realized then
			if self.get_has_window then
				move_resize (self.get_window, alloc.x, alloc.y, alloc.width, alloc.height);
			end if;

			--  send_configure event ?
		end if;

		if self.scale_to_fit_requested /= 0.0 then
			self.scale_to_fit
			(rect      => self.scale_to_fit_area,
			max_scale => self.scale_to_fit_requested);
		end if;
	end on_size_allocate;
	
	procedure view_class_init (self : gobject_class);
	pragma convention (c, view_class_init);
	
	procedure view_class_init (self : gobject_class) is begin
		set_properties_handlers (self, view_set_property'access, view_get_property'access);

		override_property (self, h_adj_property, "hadjustment");
		override_property (self, v_adj_property, "vadjustment");
		override_property (self, h_scroll_property, "hscroll-policy");
		override_property (self, v_scroll_property, "vscroll-policy");

		set_default_draw_handler (self, on_view_draw'access);
		set_default_size_allocate_handler (self, on_size_allocate'access);
		set_default_realize_handler (self, on_view_realize'access);
	end;
	
	function view_get_type return glib.gtype is
		info : access ginterface_info;
	begin
		if glib.object.initialize_class_record (
			ancestor     => gtk.bin.get_type,
			signals      => view_signals,
			class_record => view_class_record'access,
			type_name    => "GtkadaCanvasView",
			parameters   => (
				1 => (1 => gtype_none)
				),
			returns      => (1 => gtype_none, 2 => gtype_boolean),
			class_init   => view_class_init'access
			)
		then
			info := new ginterface_info' (
				interface_init     => null,
				interface_finalize => null,
				interface_data     => system.null_address);
				glib.object.add_interface (
					view_class_record,
					iface => gtk.scrollable.get_type,
					info  => info
				);
		end if;

		return view_class_record.the_type;
	end view_get_type;

	procedure layout_changed (self : not null access type_model'class) is begin
		object_callback.emit_by_name (self, signal_layout_changed);
	end layout_changed;
	
	function on_layout_changed (
		self : not null access type_model'class;
		call : not null access procedure (self : not null access gobject_record'class);
		slot : access gobject_record'class := null)
		return gtk.handlers.handler_id is
	begin
		if slot = null then
			return object_callback.connect (
				self,
				signal_layout_changed,
				object_callback.to_marshaller (call));
		else
			return object_callback.object_connect (
				self,
				signal_layout_changed,
				object_callback.to_marshaller (call),
				slot);
		end if;
	end on_layout_changed;

	procedure on_layout_changed_for_view (view : not null access gobject_record'class) is
		self  : constant type_view_ptr := type_view_ptr (view);
		alloc : gtk_allocation;
	begin
		self.get_allocation (alloc);

		--  on_adjustments_set will be called anyway when size_allocate is called
		--  so no need to call it now if the size is unknown yet.

		if alloc.width > 1 then
			set_adjustment_values (self);
			self.queue_draw;
		end if;

	end on_layout_changed_for_view;

	function intersects (rect1, rect2 : type_model_rectangle) return boolean is begin
		return not (
			rect1.x > rect2.x + rect2.width            --  r1 on the right of r2
			or else rect2.x > rect1.x + rect1.width    --  r2 on the right of r1
			or else rect1.y > rect2.y + rect2.height   --  r1 below r2
			or else rect2.y > rect1.y + rect1.height); --  r1 above r2
	end intersects;
	
	procedure for_each_item (
		self		: not null access type_model;
		callback	: not null access procedure (item : not null access type_item'class);
		in_area		: type_model_rectangle := no_rectangle)
	is
		use pac_items;
		c    : pac_items.cursor := self.items.first;
		item : type_item_ptr;
	begin
		while has_element (c) loop
			item := element (c);
			next (c);

			if (in_area = no_rectangle
				or else intersects (in_area, item.model_bounding_box))
			then
				callback (item);
			end if;
			
		end loop;
	end for_each_item;

	procedure size_request (self : not null access type_item) is
	begin
		-- CS: This is a very simple approach to get the size of the item.
		-- An advanced implementation should sample all the points of the
		-- item and figure out which one has the greatest x and y value.
		self.width  := self.c13.x;
		self.height := self.c13.y;
	end size_request;

	procedure refresh_layout (
		self        : not null access type_model;
		send_signal : boolean := true) is
		
		procedure do_size_request (item : not null access type_item'class) is begin
			type_item'class (item.all).size_request;
		end;

	begin
		-- Update the width and height of all items:
		type_model'class (self.all).for_each_item (do_size_request'access);

		if send_signal then
			type_model'class (self.all).layout_changed;
		end if;
	end refresh_layout;

	procedure set_model (
		self  : not null access type_view'class;
		model : access type_model'class) is
	begin
		if self.model = type_model_ptr (model) then
			return;
		end if;

		if self.model /= null then
			disconnect (self.model, self.id_layout_changed);
			unref (self.model);
		end if;

		self.model := type_model_ptr (model);

		if self.model /= null then
			ref (self.model);
			self.id_layout_changed := model.on_layout_changed (on_layout_changed_for_view'access, self);
		end if;

		if self.model /= null and then self.model.layout = null then
			self.model.layout := self.layout;  --  needed for layout
			ref (self.model.layout);
			self.model.refresh_layout;
		else
			set_adjustment_values (self);
			self.queue_draw;
		end if;

		self.viewport_changed;
	end set_model;

	function model_to_item (
		item   : not null access type_item'class;
		p      : type_model_rectangle) return type_item_rectangle
	is
		result : type_item_rectangle := (p.x, p.y, p.width, p.height);
		pos    : type_item_point;
	begin
		pos.x := item.position.x;
		pos.y := item.position.y;
		
		result.x := result.x - pos.x;
		result.y := result.y - pos.y;
		
		return result;
	end model_to_item;

	function model_to_item (
		item   : not null access type_item'class;
		p      : type_model_point) return type_item_point
	is
		rect   : constant type_item_rectangle := model_to_item (item, (p.x, p.y, 1.0, 1.0));
	begin
		return (rect.x, rect.y);
	end model_to_item;

	
	-- For demonstrating the difference between view coordinates (pixels) and model coordinates
	-- this function outputs them at the console.
	function on_mouse_movement (
		view  : access gtk_widget_record'class;
		event : gdk_event_motion) return boolean is
		
		-- the point where the mouse pointer is pointing at
		view_point : type_view_point;

		-- The conversion from view to model coordinates requires a pointer to
		-- the view. This command sets self so that it points to the view:
		self : constant type_view_ptr := type_view_ptr (view);

		-- The point in the model (or on the sheet) expressed in millimeters:
		model_point : type_model_point;
		
	begin
		new_line;
		put_line ("mouse movement ! new positions are:");

		-- Fetch the position of the mouse pointer and output it on the console:
		view_point := (x => event.x, y => event.y);
		put_line (" " & to_string (view_point));

		-- Convert the view point (pixels) to the position (millimeters) in the model
		-- and output in on the console:
		model_point := self.view_to_model (view_point);
		put_line (" " & to_string (model_point));

		return true; -- indicate that event has been handled
	end on_mouse_movement;

	function on_scroll_event (
		view	: access gtk_widget_record'class;
		event	: gdk_event_scroll) return boolean is
		
		self    : constant type_view_ptr := type_view_ptr (view);
		x,y		: gdouble := 0.5;
	begin
		if self.model /= null then
			new_line;
			put_line ("scroll detected");
			
		--    type Gdk_Event_Scroll is record
		--       The_Type : Gdk_Event_Type;
		--       Window : Gdk.Gdk_Window;
		--       Send_Event : Gint8;
		--       Time : Guint32;
		--       X : Gdouble;
		--       Y : Gdouble;
		--       State : Gdk.Types.Gdk_Modifier_Type;
		--       Direction : Gdk_Scroll_Direction;
		--       Device : System.Address;
		--       X_Root : Gdouble;
		--       Y_Root : Gdouble;
		--       Delta_X : Gdouble;
		--       Delta_Y : Gdouble;
		--    end record;

		end if;
		
		return true; -- indicate that event has been handled
	end on_scroll_event;
	
	function on_button_event (
		view  : access gtk_widget_record'class;
		event : gdk_event_button)
		return boolean is
	begin
		new_line;
		put_line ("mouse button pressed");
		return true; -- indicate that event has been handled
	end on_button_event;
	
	function on_key_event (
		view  : access gtk_widget_record'class;
		event : gdk_event_key) 
		return boolean is
	begin
		new_line;
		put_line ("key pressed");
		--return false;
		return true;  -- indicates to parent window that event has been handled
	end on_key_event;
	
	procedure init (
		self  : not null access type_view'class;
		model : access type_model'class := null) is
	begin
		g_new (self, view_get_type);
		self.layout := self.create_pango_layout;
		self.set_has_window (true);

		-- These are the signals the view is to receive from input devices
		-- like keyboard, mouse or touchpad:
		self.add_events (
			scroll_mask or smooth_scroll_mask or touch_mask
				or button_press_mask or button_release_mask
				or button1_motion_mask
				or button2_motion_mask
				or button3_motion_mask
				or pointer_motion_mask -- whenever the mouse is being moved inside the canvas
				-- or key_press_mask -- no need
			);

		-- reaction to keyboard in the canvas
		self.on_key_press_event (on_key_event'access);
		
		-- reaction to mouse movements in the canvas
		self.on_motion_notify_event (on_mouse_movement'access);

		-- reaction to mouse button clicks in the canvas
		self.on_button_press_event (on_button_event'access);

		-- reaction to mouse wheel being rotated
		self.on_scroll_event (on_scroll_event'access);
		
		self.set_can_focus (true);

		self.set_model (model);
	end init;

	function position (self : not null access type_item) return type_model_point is
	begin
		return self.position;
	end;
	
	procedure set_position (
		self	: not null access type_item;
		pos		: type_model_point) is
	begin
		self.position := pos;
	end;
	
	procedure gtk_new (
		self	: out type_view_ptr;
		model	: access type_model'class := null) is 
	begin
		self := new type_view;
		init (self, model);
	end;

	procedure add (
		self : not null access type_model;
		item : not null access type_item'class) is
	begin
		self.items.append (type_item_ptr (item));
	end add;

	procedure destroy_and_free (
		self     : in out type_item_ptr;
		in_model : not null access type_model'class) is
		
		procedure unchecked_free is new ada.unchecked_deallocation (type_item'class, type_item_ptr);
	begin
		if self /= null then
			unchecked_free (self);
		end if;
	end destroy_and_free;
	
	procedure remove (
		self : not null access type_model;
		item : not null access type_item'class) is
		i : type_item_ptr;
		use pac_items;
		c : pac_items.cursor;
	begin
		c := self.items.find (item);
		
		i := element (c);

		-- remove in items list
		self.items.delete (c);

		-- destroy in model
		destroy_and_free (i, self);
	end;

	procedure scale_to_fit (
		self      : not null access type_view;
		rect      : type_model_rectangle := no_rectangle;
		min_scale : gdouble := 1.0 / 4.0;
		max_scale : gdouble := 4.0)
	is
		box     : type_model_rectangle;
		w, h, s : gdouble;
		alloc   : gtk_allocation;
		tl      : type_model_point;
		wmin, hmin : gdouble;
	begin
		put_line ("scale to fit ...");
		self.get_allocation (alloc);
		if alloc.width <= 1 then
			self.scale_to_fit_requested := max_scale;
			self.scale_to_fit_area := rect;

		elsif self.model /= null then
			self.scale_to_fit_requested := 0.0;
			
			if rect = no_rectangle then
				box := self.model.bounding_box;
			else
				box := rect;
			end if;

			if box.width /= 0.0 and then box.height /= 0.0 then
						  
				w := gdouble (alloc.width);
				h := gdouble (alloc.height);

				--  the "-1.0" below compensates for rounding errors, since
				--  otherwise we are still seeing the scrollbar along the axis
				--  used to compute the scale.
				wmin := (w - 2.0 * view_margin - 1.0) / type_view_coordinate (box.width);
				hmin := (h - 2.0 * view_margin - 1.0) / type_view_coordinate (box.height);
				wmin := gdouble'min (wmin, hmin);
				s := gdouble'min (max_scale, wmin);
				s := gdouble'max (min_scale, s);

				-- calculate the new topleft corner of the visible area:
				tl := (
					x	=> box.x - (type_model_coordinate (w / s) - box.width) / 2.0,
					y	=> box.y - (type_model_coordinate (h / s) - box.height) / 2.0);

				self.scale := s;
				self.topleft := tl;
				self.set_adjustment_values;
				self.queue_draw;

			end if;
		end if;
	end scale_to_fit;


-- TEXT
	procedure initialize_text (
		self     : not null access type_text;
		style    : gtkada.style.drawing_style;
		text     : glib.utf8_string;
-- 		directed : text_arrow_direction := no_text_arrow;
		width, height : type_model_coordinate := fit_size_as_double) is
	begin
		self.style := style;
		self.text  := new string'(text);
-- 		self.directed := directed;
-- 		self.set_size (size_from_value (width), size_from_value (height));
	end initialize_text;
	
	function gtk_new_text (
		style		: gtkada.style.drawing_style;
		text		: glib.utf8_string;
-- 		directed	: text_arrow_direction := no_text_arrow;
		width, height : type_model_coordinate := fit_size_as_double)
		return type_text_ptr
	is
		r : constant type_text_ptr := new type_text;
	begin
		initialize_text (r, style, text, width, height);
		return r;
	end gtk_new_text;

	procedure set_text (
		self : not null access type_text;
		text : string) is
		use gnat.strings;
	begin
		free (self.text);
		self.text := new string'(text);
	end set_text;

	procedure draw (
		self    : not null access type_text;
		context : type_draw_context)
	is
		--text : constant string := compute_text (self);
		text : constant string := self.text.all;
	begin
-- 		resize_fill_pattern (self);
		self.style.draw_rect (context.cr, (0.0, 0.0), gdouble (self.width), gdouble (self.height));

		if context.layout /= null then
			self.style.draw_text (
				context.cr, 
				context.layout,
				(0.0, 0.0),
				text,
				max_width  => gdouble (self.width),
				max_height => gdouble (self.height)
				);
		end if;
	end draw;
	
end canvas_test;

-- Soli Deo Gloria

-- For God so loved the world that he gave 
-- his one and only Son, that whoever believes in him 
-- shall not perish but have eternal life.
-- The Bible, John 3.16
