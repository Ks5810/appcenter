// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*-
 * Copyright (c) 2014-2015 elementary LLC. (https://elementary.io)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 */

using AppCenterCore;

public class AppCenter.Views.AppListView : Gtk.ScrolledWindow {
    public signal void show_app (AppCenterCore.Package package);

    private bool _updating_cache = true;
    public bool updating_cache {
        get {
            return _updating_cache;
        }
        set {
            if (!updates_on_top) {
                warning ("updating_cache is useless if updates_on_top is false");
            }

            _updating_cache = value;
            list_box.invalidate_headers ();
        }
    }

    private bool updates_on_top;
    private Gtk.ListBox list_box;

    public AppListView (bool updates_on_top = false) {
        this.updates_on_top = updates_on_top;
        if (updates_on_top) {
            list_box.set_header_func ((row, before) => ListBoxUpdateHeaderFunc (row, before));
        }
    }

    construct {
        hscrollbar_policy = Gtk.PolicyType.NEVER;
        var alert_view = new Granite.Widgets.AlertView (_("No Apps"), _("You haven't found any app here."), "help-info");
        list_box = new Gtk.ListBox ();
        list_box.expand = true;
        list_box.activate_on_single_click = true;
        list_box.set_placeholder (alert_view);
        list_box.set_sort_func ((row1, row2) => ListBoxSortFunc (row1, row2));
        list_box.row_activated.connect ((row) => {
            var packagerow = row as Widgets.PackageRow;
            if (packagerow != null) {
                show_app (packagerow.package);
            }
        });
        add (list_box);
    }

    public void add_package (AppCenterCore.Package package) {
        var row = new Widgets.PackageRow (package);
        row.show_all ();
        list_box.add (row);
    }

    public Gee.Collection<AppCenterCore.Package> get_packages () {
        var tree_set = new Gee.TreeSet<AppCenterCore.Package> ();
        list_box.get_children ().foreach ((child) => {
            tree_set.add (((Widgets.PackageRow) child).package);
        });

        return tree_set;
    }

    private int ListBoxSortFunc (Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
        var package_a = ((Widgets.PackageRow) row1).package;
        var package_b = ((Widgets.PackageRow) row2).package;
        if (updates_on_top) {
            if (package_a.component.id == "xxx-os-updates") {
                return -1;
            } else if (package_b.component.id == "xxx-os-updates") {
                return 1;
            }

            if (package_a.update_available && !package_b.update_available) {
                return -1;
            } else if (!package_a.update_available && package_b.update_available) {
                return 1;
            }
        }

        return package_a.get_name ().collate (package_b.get_name ());
    }

    private void ListBoxUpdateHeaderFunc (Gtk.ListBoxRow row, Gtk.ListBoxRow? before) {
        bool update_available = ((Widgets.PackageRow) row).package.update_available;
        if (before == null && update_available) {
            var updates_grid = get_updates_grid ();
            row.set_header (updates_grid);
        } else if ((before == null && !update_available) || update_available != ((Widgets.PackageRow) before).package.update_available) {
            var updated_grid = get_updated_grid ();
            row.set_header (updated_grid);
        } else {
            row.set_header (null);
        }
    }

    private Gtk.Grid get_updated_grid () {
        var updated_grid = new Gtk.Grid ();
        updated_grid.orientation = Gtk.Orientation.HORIZONTAL;
        updated_grid.column_spacing = 12;
        updated_grid.margin = 6;
        if (updating_cache) {
            updated_grid.halign = Gtk.Align.CENTER;
            var updating_label = new Gtk.Label (_("Searching for updates…"));
            var spinner = new Gtk.Spinner ();
            spinner.start ();
            updated_grid.add (spinner);
            updated_grid.add (updating_label);
        } else {
            var updated_label = new Gtk.Label (_("Up to date"));
            updated_label.hexpand = true;
            ((Gtk.Misc) updated_label).xalign = 0;
            updated_label.get_style_context ().add_class ("h4");
            updated_grid.add (updated_label);
        }

        updated_grid.show_all ();
        return updated_grid;
    }

    private Gtk.Grid get_updates_grid () {
        var applications = get_packages ();
        uint update_numbers = 0U;
        uint64 update_real_size = 0ULL;
        foreach (var package in applications) {
            if (package.update_available) {
                update_numbers++;
                update_real_size += package.update_size;
            }
        }

        var updates_label = new Gtk.Label (null);
        updates_label.label = ngettext ("%u update is available.", "%u updates are available.", update_numbers).printf (update_numbers);
        ((Gtk.Misc) updates_label).xalign = 0;
        updates_label.get_style_context ().add_class ("h4");
        updates_label.hexpand = true;

        var update_size = new Gtk.Label (null);
        update_size.label = _("Size: %s").printf (GLib.format_size (update_real_size));

        var update_all_button = new Gtk.Button.with_label (_("Update All"));
        update_all_button.margin_end = 6;
        update_all_button.valign = Gtk.Align.CENTER;
        update_all_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
        update_all_button.clicked.connect (() => update_all_clicked.begin ());
        var updates_grid = new Gtk.Grid ();
        updates_grid.margin = 6;
        updates_grid.orientation = Gtk.Orientation.HORIZONTAL;
        updates_grid.column_spacing = 12;
        updates_grid.add (updates_label);
        updates_grid.add (update_size);
        updates_grid.add (update_all_button);
        updates_grid.show_all ();
        return updates_grid;
    }

    private async void update_all_clicked () {
        var applications = get_packages ();
        var treeset = new Gee.TreeSet<Package> ();
        foreach (var package in applications) {
            if (package.update_available) {
                treeset.add (package);
                package.progress = 0.0f;
            }
        }

        try {
            yield AppCenterCore.Client.get_default ().update_packages (treeset, (progress, type) => {ProgressCallback (treeset, progress, type);});
        } catch (Error e) {
            critical (e.message);
        }
        
    }

    private void ProgressCallback (Gee.TreeSet<Package> packages, Pk.Progress progress, Pk.ProgressType type) {
        if (progress.package != null) {
            foreach (var package in packages) {
                if (progress.package.get_name () in package.component.get_pkgnames ()) {
                    package.ProgressCallback (progress, type);
                    return;
                }
            }
        }

        foreach (var package in packages) {
            package.ProgressCallback (progress, type);
        }
    }
}
