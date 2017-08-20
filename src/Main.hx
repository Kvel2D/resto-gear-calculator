
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

enum State {
    State_None;
    State_Pre;
    State_Display;
}

@:publicFields
class Main {
    static inline var DEBUG = false;

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

    var items = new Map<String, Array<Item>>();
    var permutation_indices = new Map<String, Int>();

    var output_array = new Array<String>();
    var output_colors = new Array<Int>();
    var output_string = "";
    var scroll_index = 0;

    var record_number = 0;
    var time = 0;
    var tides = 0;
    var use_manaspring = false;
    var base_mana = 0;
    var buff_int = 0;
    var buff_mp5 = 0;
    var heal_amount = 0;
    var heal_cost = 0;
    var heal_is_chained = false;
    var mana_pots = 0;
    var cast_time = 0.0;

    var number_of_items = 0;
    static inline var alot_of_items = 25;

    var state = State_None;
    static inline var pre_duration = 10;
    var state_timer = 0;

    function new() {
        Gfx.resize_screen(screen_width, screen_height);
        load_items();
        state = State_Pre;
        state_timer = pre_duration;
    }

    function load_items() {
        number_of_items = 0;

        var items_file = Data.load_text("items");
        options = new Map<String, Int>();
        items = new Map<String, Array<Item>>();
        permutation_indices = new Map<String, Int>();

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
            number_of_items++;

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

        record_number = get_option('record number');
        time = get_option('time limit');
        if (time <= 0) {
            time = 10 * 60; // unlimited time, default to 10min
        }
        tides = get_option('tides');
        use_manaspring = get_option('use manaspring') == 1;
        base_mana = get_option('base mana');
        buff_int = get_option('buff int');
        buff_mp5 = get_option('buff mp5'); 
        heal_amount = get_option('heal amount');
        heal_cost = get_option('heal cost');
        heal_is_chained = get_option('heal is chained') == 1;
        mana_pots = get_option('mana pots');

        if (DEBUG) {
            for (type in types) {
                for (item in items[type]) {
                    trace('${item.name} has int=${item.stats["int"]} mp5=${item.stats["mp5"]} 
                        hsp=${item.stats["hsp"]} +mana=${item.stats["+mana"]} tier=${item.stats["tier"]}');
                }
            }
        }

        state = State_Pre;
        state_timer = pre_duration;
    }

    function calculate() {
        var top_perm = new Vector<Array<Int>>(record_number);
        var top_healed = new Vector<Int>(record_number);
        var top_t = new Vector<Int>(record_number);
        var top_stats = new Vector<String>(record_number);
        for (i in 0...top_perm.length) {
            top_perm[i] = new Array<Int>();
            top_healed[i] = 0;
        }

        // Go through every item permutation
        while (true) {

            // don't duplicate rings/trinkets
            var duplicate_finger_or_trinket = 
            permutation_indices["finger1"] == permutation_indices["finger2"]
            || permutation_indices["trinket1"] == permutation_indices["trinket2"];

            if (!duplicate_finger_or_trinket) {
                var added_mana = 0;
                var int = buff_int;
                var hsp = 0;
                var mp5 = buff_mp5;
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

                var mana = base_mana + Std.int(int * 15.75) + added_mana;

                // Simulate
                // Try cast delays from 0 to 3, find the delay that produces
                // time which is as close as possible to the limit and has highest healed amount
                var cast_delay: Float;
                for (i in 0...9) { 
                    cast_delay = i * 0.5;
                    simulate(mana, mp5, hsp, tier1, tier2, cast_delay);
                    var bigger_delay_healed = healed;
                    var bigger_delay_t = t;
                    var bigger_delay = i * 0.5;

                    // See if previous delay performed better
                    if (t >= time) {
                        if (i > 0) {
                            simulate(mana, mp5, hsp, tier1, tier2, cast_delay - 0.5);
                        }
                        break;
                    }
                }
                for (i in 0...top_healed.length) {
                    // don't add permutations with same healed
                    if (healed == top_healed[i]) {
                        break;
                    }

                    if (healed > top_healed[i]) {
                        // shift down
                        var j = top_healed.length - 1;
                        while (j > i) {
                            top_healed[j] = top_healed[j - 1];
                            top_perm[j] = top_perm[j - 1];
                            top_t[j] = top_t[j - 1];
                            top_stats[j] = top_stats[j - 1];
                            j--;
                        }
                        top_healed[i] = healed;
                        top_t[i] = Std.int(t);
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
                if (permutation_indices[type] < items[type].length - 1) {
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

                permutation_indices[types[i]]++;
                if (permutation_indices[types[i]] > items[types[i]].length - 1) {
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

        var t1_5 = (tier1 >= 5);
        var t1_8 = (tier1 >= 8);
        var t2_3 = (tier2 >= 3);

        var casts = 0;
        var healed_this_cast = 0;

        stats_mana = mana;
        stats_mp5 = mp5;
        stats_hsp = hsp;

        // apply mana tides
        mana += (4 * manatide_tick - manatide_cost) * tides;
        mana += mana_pots;

        while (true) {
            t += 0.5;
            // trace(t);
            // trace(mana);
            cast_timer -= 0.5;

            // Cast heal
            if (cast_timer < 0) {
                casts++;
                mana -= heal_cost;
                if (t1_5 && !heal_is_chained) {
                    mana += Std.int(heal_cost * 0.25 * 0.35);
                }
                cast_timer = cast_time + cast_delay;
                // extra 75% from 2 chain heal jumps
                healed_this_cast = heal_amount + hsp;
                if (heal_is_chained) {
                    if (t2_3) {
                        // 1.0 + 0.65 + 0.4= 2.05
                        // second jump gets the bonus of the first jump, source:
                        // http://elitistjerks.com:80/f31/t19181-shaman_how_heal_like_pro/
                        // April 2008 onarchive.org
                        healed_this_cast = Std.int(healed_this_cast * 2.0725);
                    } else {
                        // 1.0 + 0.5 + 0.25 = 1.75
                        healed_this_cast = Std.int(healed_this_cast * 1.75);
                    }
                } else if (t1_8 && !heal_is_chained) {
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
            if (t > time) {
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

    function update_pre() {
        if (number_of_items > alot_of_items) {
            Text.display(0, 0, 'Processing $number_of_items items, this will take a while\n
                (<25 items recommended)', Col.WHITE);
        }

        state_timer--;
        if (state_timer < 0) {
            calculate();
            state = State_Display;
        }
    }

    var last_mousewheel = -1;
    function update_display() {

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
            load_items();
            state = State_Pre;
            state_timer = pre_duration;
        });
    }

    function update() {
        switch (state) {
            case State_Pre: update_pre();
            case State_Display: update_display();
            default:
        }
    }
}
