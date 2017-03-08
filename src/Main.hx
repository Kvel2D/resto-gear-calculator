import haxegon.*;
import haxe.ds.Vector;
import flash.system.System;

@:publicFields
class Item {
    var name = "";
    var type = "";
    var stats = new Map<String, Int>();
    function new() {}
}

@:publicFields
class Main {
    static inline var screen_width = 310;
    static inline var screen_height = 200;
    static inline var DEBUG = false;

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
    "-cost",
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
    var permutation_indices_max = new Map<String, Int>();


    var top_perm: Vector<Array<Int>>;
    var top_healed: Vector<Int>;
    var top_t: Vector<Int>;
    var record_number = 0;

    function new() {
        Gfx.resize_screen(screen_width, screen_height);

        for (type in types) {
            items[type] = new Array<Item>();
            permutation_indices[type] = 0;
        }

        // Load items
        var items_file = Data.load_text("items");
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
            find_option('base mana');
            find_option('base int');
            find_option('talent crit');
            find_option('heal amount');
            find_option('heal cost');
            find_option('buff int');
            find_option('buff mp5');
            find_option('cast delay');
            find_option('mana potion');
            find_option('record number');


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


        record_number = get_option('record number');
        top_perm = new Vector<Array<Int>>(record_number);
        top_healed = new Vector<Int>(record_number);
        top_t = new Vector<Int>(record_number);
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
                        hsp=${item.stats["hsp"]} -cost=${item.stats["-cost"]} +mana=${item.stats["+mana"]}');
                }
            }
        }


        // Go through every item permutation
        while (true) {

            var added_mana = 0;
            var int = 0;
            var hsp = 0;
            var mp5 = 0 + 8 + 8;//oil and nightfin
            var cost_decrease = 0;
            var base_int = get_option('base int');

            for (type in types) {
                var item = items[type][permutation_indices[type]];
                added_mana += item.stats["+mana"];
                int += item.stats["int"];
                mp5 += item.stats["mp5"];
                hsp += item.stats["hsp"];
                cost_decrease += item.stats["-cost"];
            }

            // Simulate
            simulate(added_mana, base_int, int, mp5, hsp, cost_decrease);
            var result_healed = healed;
            var result_t = t;

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
                            j--;
                        }
                        top_healed[i] = result_healed;
                        top_t[i] = result_t;
                        var perm = new Array<Int>();
                        for (type in types) {
                            perm.push(permutation_indices[type]);
                        }
                        top_perm[i] = perm;
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

        for (j in 0...record_number) {
            if (top_healed[j] == 0) {
                break;
            }
            trace("-----------");
            trace('# ${j+1}');
            trace('Total healed: ${top_healed[j]}');
            trace('Time until 0mp: ${top_t[j]}');
            for (i in 0...types.length) {
                var type = types[i];
                var item = items[type][top_perm[j][i]];
                trace('${type}: ${item.name}');
            }
        }
    }

    static var tide_cost = 54;
    static var spring_cost = 90;

    static var manatide_timer_max = 3 * 60;
    static var manatide_length = 30;
    static var manatide_time_1 = 60;
    static var manatide_time_2 = 120;
    static var manatide_tick = 290;
    static var manaspring_tick = 12;
    static var cast_time = 3;
    var t = 0;
    var healed = 0;
    function simulate(added_mana, base_int, int, mp5, hsp, cost_decrease) {
        healed = 0;
        t = 0;
        int += get_option('buff int');
        mp5 += get_option('buff mp5');
        var mana = get_option('base mana') + Std.int(int * 15.75);
        var cast_timer = 0;
        var manatide_timer = 0;
        var manatide_on = false;
        var manaspring_on = true;
        var crit = get_option('talent crit') + Std.int(int / 60);
        var heal_amount = get_option('heal amount');
        var heal_cost = get_option('heal cost');
        var cast_delay = get_option('cast delay');
        var used_potion = false;

        while (true) {
            t++;
            // trace(t);
            // trace(mana);
            cast_timer--;
            if (manatide_on) {
                manatide_timer--;
                if (manatide_timer < 0) {
                    manatide_on = false;
                    manaspring_on = true;
                }
            } else {
                if (t == manatide_time_1 || t == manatide_time_2) {
                    manatide_on = true;
                    manaspring_on = false;
                    manatide_timer = manatide_length;
                    mana -= tide_cost;
                    mana += cost_decrease;
                }
            }

            // Cast chain heal
            if (cast_timer <= 0) {
                mana -= heal_cost;
                mana += cost_decrease;
                cast_timer = cast_time + cast_delay;
                // extra 75% from 2 chain heal jumps
                // n% casts will be critical and heal 150% the regular amount
                healed += Std.int((heal_amount + hsp) * 1.75 * (1 + crit / 100 * 0.5));
            }

            // Apply mp5
            if (t % 5 == 0) {
                mana += mp5;
            }



            // Manatide/manaspring
            if (manatide_on && t % 3 == 0) {
                mana += manatide_tick;
            } else if (manaspring_on && t % 2 == 0) {
                mana += manaspring_tick;
            }

            // actual duration is 60s, but there are 2 tides and you need to offset that
            if (t % 70 == 0) { 
                mana -= spring_cost;
                mana += cost_decrease;
            }


            // hard cap at 10min
            if (t >= 10 * 60) {
                return;
            }

            if (mana <= 0) {
                if (!used_potion) {
                    mana += get_option('mana potion');
                    used_potion = true;
                }
                if (mana <= 0) {
                    return;
                }
            }
        }
    }


    //delay between casts
    //consumables(oil, nightfin, flasks)
    //buffs
    //manaspring totem on/off
    //cast rotation(ch1, ch1/ch1/ch3, etc.)
    //crits(int increases crit a bit)

    var exit_timer = 60;
    function update() {
        exit_timer--;
        if (exit_timer <= 0) {
            System.exit(0);
        }
    }
}
