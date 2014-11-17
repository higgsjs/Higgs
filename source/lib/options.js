(function (exports)
{
    var exit = require('lib/stdlib').exit;

    /**
     * Parse an array of arguments.
     * The result is an array that contains the plain arguments.
     * The named parameters are as added on the array as key/value pairs.
     * Example:
     * ./cmd foo bar --existential --singleValue value --multipleValues values values
     */
    function parse(args)
    {
        var arguments = [];
        var parameters = {};
        var collecting = false;
        var param, values, arg, startsWithDD;

        function storeValue() {
            var val;
            // boolean parameter
            if (values.length == 0)
                val = true;
            // one value parameter
            else if (values.length == 1)
                val = values[0];
            // multiple value parameter
            else
                val = values;

            parameters[param] = val;
        }

        for (var i = 0; i < args.length; i++) {
            arg = args[i];
            startsWithDD = arg.indexOf('--') == 0;

            // check if collecting the values of a parameter
            if (collecting) {
                // check if the argument starts with --
                if (startsWithDD) {
                    // store value(s) with param
                    storeValue();
                    // prepare new param
                    param = arg.substr(2);
                    values = [];
                } else {
                    // append value
                    values.push(arg);
                }
            // not collecting
            } else {
                // if the argument does not start with --, it's a plain value.
                if (!startsWithDD) {
                    arguments.push(arg);
                } else {
                    collecting = true;
                    param = arg.substr(2);
                    values = [];
                }
            }
        }

        // handle the last item of the arguments array
        if (collecting) {
            storeValue();
        }

        return {
            arguments: arguments,
            parameters: parameters,
        };
    }

    exports.parse = parse;

    // Obtain all the stuff from setB that is not in setA.
    // setB \ setA
    // http://en.wikipedia.org/wiki/Complement_(set_theory)
    function complement(setA, setB) {
        var it, results = [];
        for (var i = 0; i < setB.length; i++) {
            it = setB[i];
            if (setA.indexOf(it) === -1) {
                results.push(it);
            }
        }
        return results;
    }

    // If there's an error, add it to the list.
    function collectErrors(errors, result) {
        // string
        if (typeof result === 'string') {
            errors.push(result);
        // array
        } else if (typeof result !== 'undefined') {
            for (var i = 0; i < result.length; i++) {
                errors.push(result[i]);
            }
        }
    }

    /**
     * Create a new Options definition.
     */
    function Options(version, usage) {
        if (!(this instanceof Options)) return new Options(version, usage);
        this._version = version;
        this._usage = usage;
        this._options = [];
    }

    /**
     * Set the amount of plain arguments required.
     * Value can be a number or an object with a min and/or max property.
     */
    Options.prototype.setArgsRule = function (props) {
        if (typeof props === 'number') {
            this._argNumber = props;
        } else {
            if (typeof props.min !== 'undefined') this._min = props.min;
            if (typeof props.max !== 'undefined') this._max = props.max;
        }
    };

    /**
     * Add a required parameter.
     */
    Options.prototype.required = function (name, desc)
    {
        this._options.push({
            name: name,
            desc: desc,
            required: true,
        });
    };

    /**
     * Add an optional parameter.
     */
    Options.prototype.optional = function (name, desc)
    {
        this._options.push({
            name: name,
            desc: desc,
            required: false,
        });
    };

    /**
     * Check the amount of arguments with the wanted amount.
     */
    Options.prototype._checkArgNumber = function (amount, argNumber)
    {
        if (typeof argNumber !== 'undefined' && argNumber !== amount) {
            return 'You must have ' + argNumber + ' arguments.';
        }
    };

    /**
     * Check the amount of arguments with the minimum amount.
     */
    Options.prototype._checkArgMin = function (amount, min)
    {
        if (typeof min !== 'undefined' && min > amount) {
            return 'You must have at least ' + min + " arguments.";
        }
    };

    /**
     * Check the amount of arguments with the maximum amount.
     */
    Options.prototype._checkArgMax = function (amount, max)
    {
        if (typeof max !== 'undefined' && max < amount) {
            return 'You must have at most ' + max + " arguments.";
        }
    };

    /**
     * Check if all the required params were given.
     */
    Options.prototype._checkParamsRequired = function (givenParams, requiredParams)
    {
        var errors = [];
        // compute the list of required arguments that were not given.
        var requiredButNotGiven = complement(givenParams, requiredParams);
        for (var i = 0; i < requiredButNotGiven.length; i++) {
            errors.push("The parameter --" + requiredButNotGiven[i] + " is required.");
        }
        return errors;
    };

    /**
     * Check the params that were given and are unknown.
     */
    Options.prototype._checkParamsUnknown = function (allParams, givenParams)
    {
        var errors = [];
        // compute the list of arguments given that are unknown.
        var givenButUnknown = complement(allParams, givenParams);
        for (var i = 0; i < givenButUnknown.length; i++) {
            errors.push("The parameter --" + givenButUnknown[i] + " is unknown.");
        }
        return errors;
    }

    /**
     * Parse the given arguments.
     * If an error occurs, the error(s) will be displayed and the program will exit.
     */
    Options.prototype.parse = function (args)
    {
        var data = parse(args);

        if (data.parameters.help) {
            this.help();
            exit(0);
        }

        if (data.parameters.version) {
            this.version();
            exit(0);
        }

        var errors = [];

        // check the number of arguments

        var amount = data.arguments.length;
        collectErrors(errors, this._checkArgNumber(amount, this._argNumber));
        collectErrors(errors, this._checkArgMin(amount, this._min));
        collectErrors(errors, this._checkArgMax(amount, this._max));

        // verifiy the params

        var getName = function (it) { return it.name; };
        var isRequired = function (it) { return it.required; };

        // all given params
        var givenParams = Object.keys(data.parameters);
        // all the known params, required + optional
        var allParams = this._options.map(getName);
        // only the required params
        var requiredParams = this._options.filter(isRequired).map(getName);

        collectErrors(errors, this._checkParamsRequired(givenParams, requiredParams));
        collectErrors(errors, this._checkParamsUnknown(allParams, givenParams));

        if (errors.length > 0) {
            this.help(errors);
            exit(1);
        } else {
            this.arguments = data.arguments;
            this.parameters = data.parameters;
        }
    };

    /**
     * Display help for this program.
     * Will automatically display and exit if --help is detected.
     */
    Options.prototype.help = function (errors)
    {
        if (typeof errors !== 'undefined') {
            print("\nErrors:\n");
            for (var i = 0; i < errors.length; i++) {
                print("\t" + errors[i]);
            }
        }
        print("\nUsage: " + this._usage);
        print("\nOptions:\n");
        for (var i = 0; i < this._options.length; i++) {
            var opt = this._options[i];
            print("\t--" + opt.name + "\t\t" + opt.desc + (opt.required ? " (required)" : ""));
        }
        print();
    }

    /**
     * Display version information for this program.
     * Will automatically display and exit if --version is detected.
     *
     */
    Options.prototype.version = function ()
    {
        print(this._version);
    };

    exports.Options = Options;

})(exports);
