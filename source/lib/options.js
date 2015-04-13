/**
    Features:
     - Argument collection
     - Long options: --long
     - Short options: -s
     - Option description
     - Default values
     - Type checking and error reporting
     - Available types: string, boolean, int, +int, float, +float
     - Type inference using the default value (when provided)
     - Automatic convertion of types (from strings)
     - Mandatory options and error reporting
     - Automatic help and version display (when turned on)

    Parsing:
        Values are assigned using an equal sign.
            --opt=val, -o=val
        Short options can be grouped together. The last
        option of a short option group can have a value:
            -abc=def c gets the value 'def'

         -a             => {a: true}
         -a=value       => {a: 'value'}
         -ab            => {a: true, b: true}
         -ab=value      => {a: true, b: 'value'}
         --long=value   => {long: 'value'}

         Anything that is not preceded by an option is considered
         a plain argument.
 */

(function (exports) {

    var exit = require('lib/stdlib').exit;
    var inst = {
        _usage: null,
        _version: null,
        _specs: [],
        _helpSpec: {long: 'help', short: null, desc: 'display this help and exit', defval: false, type: 'boolean'},
        _versionSpec: {long: 'version', short: null, desc: "output version information and exit", defval: false, type: 'boolean'},
     };

    /**
     * Create a new options parser.
     * config: (optional)
     */
    function setConfig(config)
    {
        if (config != null)
        {
            inst._usage = config.usage;
            inst._version = config.version;
            for (var i = 0; i < config.opts.length; i++)
            {
                var opt = config.opts[i];
                add(opt.long, opt.defval, opt.type, opt.desc, opt.short, opt.req);
            }
        }

        return exports;
    }
    exports.setConfig = setConfig;

    /**
     * usage: usage string
     */
    function setUsage(usage)
    {
        inst._usage = usage;
        return exports;
    };
    exports.setUsage = setUsage;

    /**
     * version: version string
     */
    function setVersion(version)
    {
        inst._version = version;
        return exports;
    };
    exports.setVersion = setVersion;

    /**
     * Format a spec for display.
     */
    function formatSpec(spec)
    {
        if (spec.long != null && spec.short != null)
            return '--' + spec.long + ', ' + '-' + spec.short;
        else if (spec.long != null)
            return '--' + spec.long;
        else if (spec.short != null)
            return '-' + spec.short;
    }

    /**
     * Add padding for indentation purposes.
     */
    function appendSpaces(str, longest)
    {
        var len = Math.max(0, longest - str.length);
        return str + Array(len + 1).join(' ');
    }

    /**
     * Display help about command.
     */
    function help()
    {
        var buff = '';
        var specs = getSpecs();

        if (inst._usage != null)
            buff += '\nUsage: ' + inst._usage +'\n';

        if (specs.length > 0)
        {
            var longestLeft = 0;
            var lefts = [];

            buff += '\nOptions:\n\n';

            // format left part of help
            for (var i = 0; i < specs.length; i++)
            {
                var left = formatSpec(specs[i]);

                // record which left is the longest for padding
                longestLeft = Math.max(longestLeft, left.length);
                lefts.push(left);
            }

            // create the lines
            for (var i = 0; i < specs.length; i++)
            {
                var spec = specs[i];
                var line = '    ' + appendSpaces(lefts[i], longestLeft);
                if (spec.desc != null)
                    line += '    ' + spec.desc;
                buff += line + '\n';
            }
        }

        print(buff);
    };
    exports.help = help;

    /**
     * long: long option name (or an object with these params as keys)
     * short: short option name
     * desc: description of option
     * defval: default value
     * type: type of data (valid types: string, int, +int, float, +float, boolean)
     * req: required
     */
    function add(long, defval, type, desc, short, req)
    {
        if (arguments.length === 1 && long !== null && typeof(long) === "object") {
            var opts = long;
            long = opts.long;
            defval = opts.defval;
            type = opts.type;
            desc = opts.desc;
            short = opts.short;
            req = opts.req;
        }
        // try to infer the type when possible
        if (type == null)
        {
            if (defval == null)
            {
                type = 'string';
            }
            else
            {
                // infer from default value
                if ($ir_is_string(defval))
                    type = 'string';
                else if ($ir_is_int32(defval))
                    type = 'int';
                else if ($ir_is_float64(defval))
                    type = 'float';
                else if (typeof defval === 'boolean')
                    type = 'boolean';
            }
        }

        inst._specs.push({
            long: long,
            short: short,
            desc: desc,
            defval: defval,
            type: type,
            req: req,
        });

        return exports;
    };
    exports.add = add;

    /**
     * args: command line arguments
     *
     * Accepted patterns for parameters:
     *  -a             => {a: true}
     *  -ab            => {a: true, b: true}
     *  -ab=value      => {a: true, b: value}
     *  --long=value   => {long: value}
     */
    function parse(argv)
    {
        var p = parseArgv(argv);
        var opts = p.opts;
        var results = {};
        var specs = getSpecs();
        for (var i = 0; i < specs.length; i++)
        {
            var spec = specs[i];
            // check if long option is present
            var val = getValue(opts, spec);

            // if there is a value, use it
            if (val != null)
            {
                // validate value
                if ((typeof val === 'boolean' && spec.type !== 'boolean') || !typeTests[spec.type](val))
                {
                    printAndExit('Invalid type for ' + formatSpec(spec) + '. Expected ' + typeToString[spec.type] + ".");
                }

                // convert from string to spec.type
                val = convertValue(val, spec.type);

                applyValue(results, spec, val);
            }
            // fallback to default value if present
            else if (spec.defval != null)
            {
                applyValue(results, spec, spec.defval);
            }
            else if (spec.req === true)
            {
                printAndExit('The option ' + formatSpec(spec) + ' is required.');
            }
        }

        results._ = p.args;

        if (results.help === true)
        {
            help();
            exit(0);
        }

        if (inst._version != null && results.version === true)
        {
            printAndExit(inst._version, 0);
        }

        return results;
    };
    exports.parse = parse;

    /**
     * Get the list of specs and append the helpSpec and versionSpec if they're activated.
     */
    function getSpecs()
    {
        var arr = inst._specs.slice();
        if (inst._usage != null)
            arr = arr.concat(inst._helpSpec);
        if (inst._version != null)
            arr = arr.concat(inst._versionSpec);
        return arr;
    }

    /**
     * arg: argument to parse
     * options: options object to modify
     */
    function parseOption(arg, options)
    {
        // long option regex
        var matches = arg.match(/^--([a-z0-9_\-]+)(?:=(.+))?$/i);
        if (matches !== null)
        {
            options[matches[1]] = matches[2] || true;
        }
        else
        {
            // short option regex
            matches = arg.match(/^-([a-z]+)(?:=(.+))?$/i);
            // check if parameter is valid
            if (matches !== null)
            {
                // split the options -abc = {a:true,b:true,c:true}
                for (var i = 1; i < arg.length; i++)
                    options[arg[i]] = true;
                // if there's a value, give it to the last option
                // -abc=qwerty {a:true,b:true,c:'qwerty'}
                if (matches[2] != null)
                {
                    var opt = matches[1].slice(-1);
                    options[opt] = matches[2];
                }
            } else {
                throw new Error('Invalid option: ' + arg);
            }
        }
    }
    exports._parseOption = parseOption;

    /**
     * argv: argument vector, list of arguments
     */
    function parseArgv(argv)
    {
        var arguments = [];
        var options = {};
        for (var i = 0; i < argv.length; i++)
        {
            var arg = argv[i];
            if (/^--?/.test(arg))
            {
                parseOption(arg, options);
            }
            else
            {
                arguments.push(arg);
            }
        }
        return {args: arguments, opts: options};
    }
    exports._parseArgv = parseArgv;

    /**
     * Anything is valid.
     */
    function testString()
    {
        return true;
    }

    /**
     *    33 | -33
     *   33. | -33.
     *   .33 | -.33
     * 33.33 | -33.33
     */
    function testFloat(val)
    {
        return /^\-?([0-9]+|[0-9]+\.|\.[0-9]+|[0-9]+\.[0-9]+)$/.test(val);
    }
    exports._testFloat = testFloat;

    /**
     * Same as testFloat, but no negative numbers.
     */
    function testFloatPositive(val)
    {
        return /^([0-9]+|[0-9]+\.|\.[0-9]+|[0-9]+\.[0-9]+)$/.test(val);
    }
    exports._testFloatPositive = testFloatPositive;

    /**
     * 33 | -33
     */
    function testInt(val)
    {
        return /^\-?[0-9]+$/.test(val);
    }
    exports._testInt = testInt;

    /**
     * Same as testInt, but no negative numbers.
     */
    function testIntPositive(val)
    {
        return /^[0-9]+$/.test(val);
    }
    exports._testIntPositive = testIntPositive;

    /**
     * Accepts a boolean, or the strings 'on', 'yes', 'true', 'off', 'no', 'false'
     */
    function testBoolean(val)
    {
        if ($ir_is_string(val))
            return /^(1|on|yes|true|0|off|no|false)$/i.test(val);
        else if (typeof val === 'boolean')
            return true;
        return false;
    }
    exports._testBoolean = testBoolean;

    /**
     * Data validity tests by type.
     */
    var typeTests = {
        'string': testString,
        'float': testFloat,
        '+float': testFloatPositive,
        'int': testInt,
        '+int': testIntPositive,
        'boolean': testBoolean,
    };

    /**
     * Map from type to "English" equivalent.
     */
    var typeToString = {
        'string': 'a string',
        'float': 'a floating point number',
        '+float': 'a positive floating point number',
        'int': 'an integer',
        '+int': 'a positive integer',
        'boolean': 'a boolean',
    };

    /**
     * Convert the string value to the correct type when possible.
     * val: string value
     * type: type of value
     */
    function convertValue(val, type)
    {
        switch (type) {
            case 'float':
            case '+float':
                return parseFloat(val);
            case 'int':
            case '+int':
                return parseInt(val);
            case 'boolean':
                if ($ir_is_string(val))
                {
                    if (/^(1|on|yes|true)$/i.test(val)) return true;
                    else if (/^(0|off|no|false)$/i.test(val)) return false;
                }
                return val;
            default:
                return val;
        }
    }
    exports._convertValue = convertValue;

    /**
    * opts: options that were parsed
    * spec: specification of the option
    */
    function getValue(opts, spec)
    {
        if (opts[spec.long] != null) return opts[spec.long];
        if (opts[spec.short] != null) return opts[spec.short];
        return null;
    }

    /**
    * results: result object to modify
    * spec: specification for the option
    * val: value to apply
    */
    function applyValue(results, spec, val)
    {
        if (spec.long != null)
        results[spec.long] = val;
        if (spec.short != null)
        results[spec.short] = val;
    }

    /**
     * Print
     * str: string to print
     * code: return code (defaults to 1)
     */
    function printAndExit(str, code)
    {
        print(str);
        exit(code != null ? code : 1);
    }

})(exports);
