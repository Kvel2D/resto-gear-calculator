
import haxegon.*;
import haxe.ds.Vector;
import flash.system.System;
#if cpp
import sys.io.File;
import sys.FileSystem;
#end

@:publicFields
class Item {
    var name = "";
    var type = "";
    var stats = new Map<String, Int>();
    function new() {}
}

@:publicFields
class Main {
    static inline var DEBUG = false;
    static inline var AUTO_EXIT = false;

    static inline var screen_width = 1000;
    static inline var screen_height = 1000;
    
    var types = [
    "head",
    "neck",
    "shoulder",
    "back",
    "chest",
    "wrist",
    "hands",
    "waist",
    "legs",
    "feet",
    "finger1",
    "finger2",
    "trinket1",
    "trinket2",
    "weapon",
    "offhand",
    ];

    var stats = [
    "int",
    "mp5",
    "hsp",
    "+mana",
    "tier",
    ];

    var options = new Map<String, Int>();
    function get_option(name: String): Int {
        if (options.exists(name)) {
            return options[name];
        } else {
            trace('COULDN\'T FIND OPTION $name');
            return 0;
        }
    }

    var top_perm: Vector<Array<Int>>;
    var top_healed: Vector<Int>;
    var top_t: Vector<Int>;
    var top_stats: Vector<String>;

    var output_array = new Array<String>();
    var output_colors = new Array<Int>();
    var output_string = "";
    var scroll_index = 0;

    function new() {
        Gfx.resize_screen(screen_width, screen_height);
        var items_file = Data.load_text("items");
        calculate(items_file);
    }

    function calculate(items_file: Array<String>) {

        options = new Map<String, Int>();
        var items = new Map<String, Array<Item>>();
        var permutation_indices = new Map<String, Int>();
        var permutation_indices_max = new Map<String, Int>();

        for (type in types) {
            items[type] = new Array<Item>();
            permutation_indices[type] = 0;
        }

        output_array = new Array<String>();
        output_colors = new Array<Int>();


        for (line in items_file) {
            // skip comments
            if (line.indexOf('//') != -1) {
                continue;
            }

            function find_option(name) {
                if (line.indexOf('$name =') != -1) {
                    var substr = line.substr(line.indexOf('=') + 1);
                    options[name] = Std.parseInt(substr);
                    if (DEBUG) {
                        trace(name);
                        trace(options[name]);
                    }
                }
            }
            find_option('record number');
            find_option('time limit');
            find_option('tides');
            find_option('use manaspring');
            find_option('base mana');
            find_option('buff int');
            find_option('buff mp5');
            find_option('heal amount');
            find_option('heal cost');
            find_option('heal is chained');
            find_option('mana pots');


            // item lines must have [ and ]
            if (line.indexOf('[') == -1 || line.indexOf(']') == -1) {
                continue;
            }

            var item = new Item();

            var name_start = line.indexOf("\"") + 1;
            var name_end = line.substr(name_start).indexOf("\"");
            item.name = line.substr(name_start, name_end);

            var type_start = line.indexOf("type=") + 5;
            var type_end = line.substr(type_start).indexOf(" ");
            var type = line.substr(type_start, type_end).toLowerCase();

            if (type == "finger" || type == "trinket") {
                items['${type}1'].push(item);
                items['${type}2'].push(item);
            } else if (types.indexOf(type) != -1) {
                items[type].push(item);
            } else {
                trace('$type is not a valid type!');
                continue;
            }

            item.type = type;

            var loop_stop = 20;
            var loop_count = 0;
            var substr = line.substr(type_start + type_end);
            while (substr.indexOf("=") != -1) {
                var delim = substr.indexOf("=");
                var stat_name_start = substr.substr(0, delim).indexOf(" ") + 1;
                var stat_name = substr.substring(stat_name_start, delim);
                var stat_value = Std.parseInt(substr.substr(delim + 1));
                substr = substr.substr(delim + 1);

                item.stats[stat_name] = stat_value;

                loop_count++;
                if (loop_count > loop_stop) {
                    break;
                }
            }

            // Fill out undefined stats
            for (stat in stats) {
                if (!item.stats.exists(stat)) {
                    item.stats[stat] = 0;
                }
            }
        }


        var record_number = get_option('record number');
        top_perm = new Vector<Array<Int>>(record_number);
        top_healed = new Vector<Int>(record_number);
        top_t = new Vector<Int>(record_number);
        top_stats = new Vector<String>(record_number);
        for (i in 0...top_perm.length) {
            top_perm[i] = new Array<Int>();
            top_healed[i] = 0;
        }


        for (type in types) {
            permutation_indices_max[type] = items[type].length;
        }


        if (DEBUG) {
            for (type in types) {
                for (item in items[type]) {
                    trace('${item.name} has int=${item.stats["int"]} mp5=${item.stats["mp5"]} 
                        hsp=${item.stats["hsp"]} +mana=${item.stats["+mana"]}');
                }
            }
        }


        // Go through every item permutation
        while (true) {

            var added_mana = 0;
            var int = get_option('buff int');
            var hsp = 0;
            var mp5 = get_option('buff mp5');
            var tier1 = 0;
            var tier2 = 0;

            for (type in types) {
                var item = items[type][permutation_indices[type]];
                added_mana += item.stats["+mana"];
                int += item.stats["int"];
                mp5 += item.stats["mp5"];
                hsp += item.stats["hsp"];

                if (item.stats["tier"] == 1) {
                    tier1++;
                } else if (item.stats["tier"] == 2) {
                    tier2++;
                }
            }

            var mana = get_option('base mana') + Std.int(int * 15.75) + added_mana;

            // Simulate
            // Try cast delays from 0 to 2, find the delay that produces
            // time which is as close as possible to the limit and has highest healed amount
            var time_limit = get_option('time limit');
            for (i in 0...8) {
                simulate(mana, mp5, hsp, tier1, tier2, i * 0.5);
                var bigger_delay_healed = healed;
                var bigger_delay_t = t;
                var bigger_delay = i * 0.5;

                // See if previous delay performed better
                if (t >= time_limit) {
                    if (i > 0) {
                        simulate(mana, mp5, hsp, tier1, tier2, (i - 1) * 0.5);
                    }
                    break;
                }
            }
            var result_healed = healed;
            var result_t = Std.int(t);

            // Check if new record
            // don't duplicate rings/trinkets
            var duplicate_finger_or_trinket = 
            permutation_indices["finger1"] == permutation_indices["finger2"]
            || permutation_indices["trinket1"] == permutation_indices["trinket2"];

            if (!duplicate_finger_or_trinket) {
                for (i in 0...top_healed.length) {
                    // don't add permutations with same healed
                    if (result_healed == top_healed[i]) {
                        break;
                    }

                    if (result_healed > top_healed[i]) {
                        // shift down
                        var j = top_healed.length - 1;
                        while (j > i) {
                            top_healed[j] = top_healed[j - 1];
                            top_perm[j] = top_perm[j - 1];
                            top_t[j] = top_t[j - 1];
                            top_stats[j] = top_stats[j - 1];
                            j--;
                        }
                        top_healed[i] = result_healed;
                        top_t[i] = result_t;
                        var perm = new Array<Int>();
                        for (type in types) {
                            perm.push(permutation_indices[type]);
                        }
                        top_perm[i] = perm;
                        top_stats[i] = 'mana=${stats_mana} mp5=${stats_mp5} hsp=${stats_hsp}';
                        if (tier1 >= 8) {
                            top_stats[i] += " (t1 8/8 bonus)";
                        } else if (tier1 >= 5) {
                            top_stats[i] += " (t1 5/8 bonus)";
                        }
                        if (tier2 >= 3) {
                            top_stats[i] += " (t2 3/8 bonus)";
                        }
                        break;
                    }
                }
            }

            // Done when all indices are max
            var done = true;
            for (type in types) {
                if (permutation_indices[type] < permutation_indices_max[type] - 1) {
                    done = false;
                    break;
                }
            }
            if (done) {
                break;
            }

            // Generate next permutation
            var while_loop = true;
            var i = 0;
            while (while_loop) {
                while_loop = false;

                // var str = "";
                // for (type in types) {
                //     str += permutation_indices[type];
                // }
                // trace(str);

                permutation_indices[types[i]]++;
                if (permutation_indices[types[i]] >= permutation_indices_max[types[i]]) {
                    permutation_indices[types[i]] = 0;
                    i++;
                    while_loop = true;
                }
            }
        }

        function output(line) {
            output_array.push(line);
            output_string += '\n' + line;
        }

        for (j in 0...record_number) {
            if (top_healed[j] == 0) {
                break;
            }
            output("-----------");
            output('# ${j+1}');
            output('Stats: ${top_stats[j]}');
            output('Total healed: ${top_healed[j]}');
            output('Time until 0mp: ${top_t[j]}');

            for (i in 0...5) {
                output_colors.push(Col.WHITE);
            }
            for (i in 0...types.length) {
                var type = types[i];
                var item = items[type][top_perm[j][i]];
                output('${type}: ${item.name}');
                if (j > 0 && top_perm[j][i] != top_perm[0][i]) {
                    output_colors.push(Col.GREEN);
                } else {
                    output_colors.push(Col.WHITE);
                }
            }
        }
    }

    static inline var manatide_cost = 45;
    static inline var manaspring_cost = 90;
    static inline var manatide_tick = 290;
    static inline var manaspring_tick = 12;

    static var stats_mana = 0;
    static var stats_mp5 = 0;
    static var stats_hsp = 0;

    var t: Float = 0;
    var healed = 0;
    function simulate(mana, mp5, hsp, tier1, tier2, cast_delay) {
        healed = 0;
        t = 0;
        var cast_timer: Float = 0;

        var time_limit = get_option('time limit');
        var tides = get_option('tides');
        var use_manaspring = get_option('use manaspring') == 1;
        var heal_amount = get_option('heal amount');
        var heal_cost = get_option('heal cost');
        var cast_time = 2.5;
        var chain_heal = get_option('heal is chained') == 1;

        var t1_5 = (tier1 >= 5);
        var t1_8 = (tier1 >= 8);
        var t2_3 = (tier1 >= 3);
        if (time_limit <= 0) {
            time_limit = 10 * 60;
        }

        var casts = 0;
        var healed_this_cast = 0;

        stats_mana = mana;
        stats_mp5 = mp5;
        stats_hsp = hsp;

        // apply mana tides
        mana += (4 * manatide_tick - manatide_cost) * get_option('tides');
        mana += get_option('mana pots');

        while (true) {
            t += 0.5;
            // trace(t);
            // trace(mana);
            cast_timer -= 0.5;

            // Cast heal
            if (cast_timer < 0) {
                casts++;
                mana -= heal_cost;
                if (t1_5 && !chain_heal) {
                    mana += Std.int(heal_cost * 0.25 * 0.35);
                }
                cast_timer = cast_time + cast_delay;
                // extra 75% from 2 chain heal jumps
                healed_this_cast = heal_amount + hsp;
                if (chain_heal) {
                    if (t2_3) {
                        healed_this_cast = Std.int(healed_this_cast * 1.975);
                    } else {
                        healed_this_cast = Std.int(healed_this_cast * 1.75);
                    }
                } else if (t1_8) {
                    healed_this_cast = Std.int(healed_this_cast * 1.75);
                }
                healed += healed_this_cast;
            }

            // Apply mp5
            if (Math.abs(t) % 5 < 0.1) {
                mana += mp5;
            }

            // Manaspring
            if (use_manaspring) {
                if (Math.abs(t) % 2 < 0.1) {
                    mana += manaspring_tick;
                }
                if (Math.abs(t) % 70 < 0.1) { 
                    mana -= manaspring_cost;
                }
            }


            // Caps
            // time limit cap
            if (t > time_limit) {
                return;
            }
            // mana cap
            if (mana <= 0) {
                if (mana <= 0) {
                    return;
                }
            }
            // hard cap at 20min if something goes wrong
            if (t >= 20 * 60) {
                return;
            }
        }
    }

    var last_mousewheel = -1;
    var exit_timer = 60;
    function update() {
        if (AUTO_EXIT) {
            exit_timer--;
            if (exit_timer <= 0) {
                System.exit(0);
            }
        }

        if (last_mousewheel == -1) {
            last_mousewheel = Mouse.mousewheel;
        }
        var d_mousewheel = Mouse.mousewheel - last_mousewheel;
        if (Input.pressed(Key.UP) || d_mousewheel > 0) {
            scroll_index -= 2;
            if (scroll_index < 0) {
                scroll_index = 0;
            }
        }
        if (Input.pressed(Key.DOWN) || d_mousewheel < 0) {
            scroll_index += 2;
            if (scroll_index > output_array.length - 20) {
                scroll_index = output_array.length - 20;
            }
        }

        var y = 50.0;
        for (i in scroll_index...scroll_index + 50) {
            Text.display(0, y, output_array[i], output_colors[i]);
            y += Text.height();
            if (y > screen_height) {
                break;
            }
        }

        GUI.text_button(0, 0, "Recalculate", function() { 
            var items_file = Data.load_text("items"); 
            calculate(items_file); 
        });
    }
}
