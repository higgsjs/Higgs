
/*
 * Copyright (C) 2007 Apple Inc.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

/*
    Portions from:
    json.js
    2007-10-10

    Public Domain
*/

// This test parses a JSON string giving tag names and popularity, and
// generates html markup for a "tagcloud" view.

if (!Object.prototype.toJSONString) {

    Array.prototype.toJSONString = function (w) {
        var a = [],     // The array holding the partial texts.
            i,          // Loop counter.
            l = this.length,
            v;          // The value to be stringified.

  /* BEGIN LOOP */
        for (i = 0; i < l; i += 1) {
            v = this[i];
            switch (typeof v) {
            case 'object':

                if (v && typeof v.toJSONString === 'function') {
                    a.push(v.toJSONString(w));
                } else {
                    a.push('null');
                }
                break;

            case 'string':
            case 'number':
            case 'boolean':
                a.push(v.toJSONString());
                break;
            default:
                a.push('null');
            }
        }
  /* END LOOP */

        return '[' + a.join(',') + ']';
    };


    Boolean.prototype.toJSONString = function () {
        return String(this);
    };


    Date.prototype.toJSONString = function () {

        function f(n) {

            return n < 10 ? '0' + n : n;
        }

        return '"' + this.getUTCFullYear()   + '-' +
                   f(this.getUTCMonth() + 1) + '-' +
                   f(this.getUTCDate())      + 'T' +
                   f(this.getUTCHours())     + ':' +
                   f(this.getUTCMinutes())   + ':' +
                   f(this.getUTCSeconds())   + 'Z"';
    };


    Number.prototype.toJSONString = function () {

        return isFinite(this) ? String(this) : 'null';
    };


    Object.prototype.toJSONString = function (w) {
        var a = [],     // The array holding the partial texts.
            k,          // The current key.
            i,          // The loop counter.
            v;          // The current value.

        if (w) {
  /* BEGIN LOOP */
            for (i = 0; i < w.length; i += 1) {
                k = w[i];
                if (typeof k === 'string') {
                    v = this[k];
                    switch (typeof v) {
                    case 'object':

                        if (v) {
                            if (typeof v.toJSONString === 'function') {
                                a.push(k.toJSONString() + ':' +
                                       v.toJSONString(w));
                            }
                        } else {
                            a.push(k.toJSONString() + ':null');
                        }
                        break;

                    case 'string':
                    case 'number':
                    case 'boolean':
                        a.push(k.toJSONString() + ':' + v.toJSONString());

                    }
                }
            }
  /* END LOOP */
        } else {

  /* BEGIN LOOP */
            for (k in this) {
                if (typeof k === 'string' &&
                        Object.prototype.hasOwnProperty.apply(this, [k])) {
                    v = this[k];
                    switch (typeof v) {
                    case 'object':

                        if (v) {
                            if (typeof v.toJSONString === 'function') {
                                a.push(k.toJSONString() + ':' +
                                       v.toJSONString());
                            }
                        } else {
                            a.push(k.toJSONString() + ':null');
                        }
                        break;

                    case 'string':
                    case 'number':
                    case 'boolean':
                        a.push(k.toJSONString() + ':' + v.toJSONString());

                    }
                }
            }
  /* END LOOP */
        }

        return '{' + a.join(',') + '}';
    };


    (function (s) {

        var m = {
            '\b': '\\b',
            '\t': '\\t',
            '\n': '\\n',
            '\f': '\\f',
            '\r': '\\r',
            '"' : '\\"',
            '\\': '\\\\'
        };


        s.parseJSON = function (filter) {
            var j;

            function walk(k, v) {
                var i, n;
                if (v && typeof v === 'object') {
  /* BEGIN LOOP */
                    for (i in v) {
                        if (Object.prototype.hasOwnProperty.apply(v, [i])) {
                            n = walk(i, v[i]);
                            if (n !== undefined) {
                                v[i] = n;
                            }
                        }
                    }
  /* END LOOP */
                }
                return filter(k, v);
            }

            if (/^[\],:{}\s]*$/.test(this.replace(/\\./g, '@').
                    replace(/"[^"\\\n\r]*"|true|false|null|-?\d+(?:\.\d*)?(:?[eE][+\-]?\d+)?/g, ']').
                    replace(/(?:^|:|,)(?:\s*\[)+/g, ''))) {

                j = eval('(' + this + ')');

                return typeof filter === 'function' ? walk('', j) : j;
            }

            throw new SyntaxError('parseJSON');
        };


        s.toJSONString = function () {

            if (/["\\\x00-\x1f]/.test(this)) {
                return '"' + this.replace(/[\x00-\x1f\\"]/g, function (a) {
                    var c = m[a];
                    if (c) {
                        return c;
                    }
                    c = a.charCodeAt();
                    return '\\u00' + Math.floor(c / 16).toString(16) +
                                               (c % 16).toString(16);
                }) + '"';
            }
            return '"' + this + '"';
        };
    })(String.prototype);
}

var tagInfoJSON = '[\n  {\n    \"tag\": "titillation",\n    \"popularity\": 4294967296\n  },\n  {\n    \"tag\": "foamless",\n    \"popularity\": 1257718401\n  },\n  {\n    \"tag\": "snarler",\n    \"popularity\": 613166183\n  },\n  {\n    \"tag\": "multangularness",\n    \"popularity\": 368304452\n  },\n  {\n    \"tag\": "Fesapo unventurous",\n    \"popularity\": 248026512\n  },\n  {\n    \"tag\": "esthesioblast",\n    \"popularity\": 179556755\n  },\n  {\n    \"tag\": "echeneidoid",\n    \"popularity\": 136641578\n  },\n  {\n    \"tag\": "embryoctony",\n    \"popularity\": 107852576\n  },\n  {\n    \"tag\": "undilatory",\n    \"popularity\": 87537981\n  },\n  {\n    \"tag\": "predisregard",\n    \"popularity\": 72630939\n  },\n  {\n    \"tag\": "allergenic",\n    \"popularity\": 61345190\n  },\n  {\n    \"tag\": "uncloudy",\n    \"popularity\": 52580571\n  },\n  {\n    \"tag\": "unforeseeably",\n    \"popularity\": 45628109\n  },\n  {\n    \"tag\": "sturniform",\n    \"popularity\": 40013489\n  },\n  {\n    \"tag\": "anesthetize",\n    \"popularity\": 35409226\n  },\n  {\n    \"tag\": "ametabolia",\n    \"popularity\": 31583050\n  },\n  {\n    \"tag\": "angiopathy",\n    \"popularity\": 28366350\n  },\n  {\n    \"tag\": "sultanaship",\n    \"popularity\": 25634218\n  },\n  {\n    \"tag\": "Frenchwise",\n    \"popularity\": 23292461\n  },\n  {\n    \"tag\": "cerviconasal",\n    \"popularity\": 21268909\n  },\n  {\n    \"tag\": "mercurialness",\n    \"popularity\": 19507481\n  },\n  {\n    \"tag\": "glutelin venditate",\n    \"popularity\": 17964042\n  },\n  {\n    \"tag\": "acred overblack",\n    \"popularity\": 16603454\n  },\n  {\n    \"tag\": "Atik",\n    \"popularity\": 15397451\n  },\n  {\n    \"tag\": "puncturer",\n    \"popularity\": 14323077\n  },\n  {\n    \"tag\": "pukatea",\n    \"popularity\": 13361525\n  },\n  {\n    \"tag\": "suberize",\n    \"popularity\": 12497261\n  },\n  {\n    \"tag\": "Godfrey",\n    \"popularity\": 11717365\n  },\n  {\n    \"tag\": "tetraptote",\n    \"popularity\": 11011011\n  },\n  {\n    \"tag\": "lucidness",\n    \"popularity\": 10369074\n  },\n  {\n    \"tag\": "tartness",\n    \"popularity\": 9783815\n  },\n  {\n    \"tag\": "axfetch",\n    \"popularity\": 9248634\n  },\n  {\n    \"tag\": "preacquittal",\n    \"popularity\": 8757877\n  },\n  {\n    \"tag\": "matris",\n    \"popularity\": 8306671\n  },\n  {\n    \"tag\": "hyphenate",\n    \"popularity\": 7890801\n  },\n  {\n    \"tag\": "semifabulous",\n    \"popularity\": 7506606\n  },\n  {\n    \"tag\": "oppressiveness",\n    \"popularity\": 7150890\n  },\n  {\n    \"tag\": "Protococcales",\n    \"popularity\": 6820856\n  },\n  {\n    \"tag\": "unpreventive",\n    \"popularity\": 6514045\n  },\n  {\n    \"tag\": "Cordia",\n    \"popularity\": 6228289\n  },\n  {\n    \"tag\": "Wakamba leaflike",\n    \"popularity\": 5961668\n  },\n  {\n    \"tag\": "dacryoma",\n    \"popularity\": 5712480\n  },\n  {\n    \"tag\": "inguinal",\n    \"popularity\": 5479211\n  },\n  {\n    \"tag\": "responseless",\n    \"popularity\": 5260507\n  },\n  {\n    \"tag\": "supplementarily",\n    \"popularity\": 5055158\n  },\n  {\n    \"tag\": "emu",\n    \"popularity\": 4862079\n  },\n  {\n    \"tag\": "countermeet",\n    \"popularity\": 4680292\n  },\n  {\n    \"tag\": "purrer",\n    \"popularity\": 4508918\n  },\n  {\n    \"tag\": "Corallinaceae",\n    \"popularity\": 4347162\n  },\n  {\n    \"tag\": "speculum",\n    \"popularity\": 4194304\n  },\n  {\n    \"tag\": "crimpness",\n    \"popularity\": 4049690\n  },\n  {\n    \"tag\": "antidetonant",\n    \"popularity\": 3912727\n  },\n  {\n    \"tag\": "topeewallah",\n    \"popularity\": 3782875\n  },\n  {\n    \"tag\": "fidalgo ballant",\n    \"popularity\": 3659640\n  },\n  {\n    \"tag\": "utriculose",\n    \"popularity\": 3542572\n  },\n  {\n    \"tag\": "testata",\n    \"popularity\": 3431259\n  },\n  {\n    \"tag\": "beltmaking",\n    \"popularity\": 3325322\n  },\n  {\n    \"tag\": "necrotype",\n    \"popularity\": 3224413\n  },\n  {\n    \"tag\": "ovistic",\n    \"popularity\": 3128215\n  },\n  {\n    \"tag\": "swindlership",\n    \"popularity\": 3036431\n  },\n  {\n    \"tag\": "augustal",\n    \"popularity\": 2948792\n  },\n  {\n    \"tag\": "Titoist",\n    \"popularity\": 2865047\n  },\n  {\n    \"tag\": "trisoctahedral",\n    \"popularity\": 2784963\n  },\n  {\n    \"tag\": "sequestrator",\n    \"popularity\": 2708327\n  },\n  {\n    \"tag\": "sideburns",\n    \"popularity\": 2634939\n  },\n  {\n    \"tag\": "paraphrasia",\n    \"popularity\": 2564616\n  },\n  {\n    \"tag\": "graminology unbay",\n    \"popularity\": 2497185\n  },\n  {\n    \"tag\": "acaridomatium emargination",\n    \"popularity\": 2432487\n  },\n  {\n    \"tag\": "roofward",\n    \"popularity\": 2370373\n  },\n  {\n    \"tag\": "lauder",\n    \"popularity\": 2310705\n  },\n  {\n    \"tag\": "subjunctive",\n    \"popularity\": 2253354\n  },\n  {\n    \"tag\": "subelongate",\n    \"popularity\": 2198199\n  },\n  {\n    \"tag\": "guacimo",\n    \"popularity\": 2145128\n  },\n  {\n    \"tag\": "cockade",\n    \"popularity\": 2094033\n  },\n  {\n    \"tag\": "misgauge",\n    \"popularity\": 2044818\n  },\n  {\n    \"tag\": "unexpensive",\n    \"popularity\": 1997388\n  },\n  {\n    \"tag\": "chebel",\n    \"popularity\": 1951657\n  },\n  {\n    \"tag\": "unpursuing",\n    \"popularity\": 1907543\n  },\n  {\n    \"tag\": "kilobar",\n    \"popularity\": 1864969\n  },\n  {\n    \"tag\": "obsecration",\n    \"popularity\": 1823863\n  },\n  {\n    \"tag\": "nacarine",\n    \"popularity\": 1784157\n  },\n  {\n    \"tag\": "spirituosity",\n    \"popularity\": 1745787\n  },\n  {\n    \"tag\": "movableness deity",\n    \"popularity\": 1708692\n  },\n  {\n    \"tag\": "exostracism",\n    \"popularity\": 1672816\n  },\n  {\n    \"tag\": "archipterygium",\n    \"popularity\": 1638104\n  },\n  {\n    \"tag\": "monostrophic",\n    \"popularity\": 1604506\n  },\n  {\n    \"tag\": "gynecide",\n    \"popularity\": 1571974\n  },\n  {\n    \"tag\": "gladden",\n    \"popularity\": 1540462\n  },\n  {\n    \"tag\": "throughbred",\n    \"popularity\": 1509927\n  },\n  {\n    \"tag\": "groper",\n    \"popularity\": 1480329\n  },\n  {\n    \"tag\": "Xenosaurus",\n    \"popularity\": 1451628\n  },\n  {\n    \"tag\": "photoetcher",\n    \"popularity\": 1423788\n  },\n  {\n    \"tag\": "glucosid",\n    \"popularity\": 1396775\n  },\n  {\n    \"tag\": "Galtonian",\n    \"popularity\": 1370555\n  },\n  {\n    \"tag\": "mesosporic",\n    \"popularity\": 1345097\n  },\n  {\n    \"tag\": "theody",\n    \"popularity\": 1320370\n  },\n  {\n    \"tag\": "zaffer",\n    \"popularity\": 1296348\n  },\n  {\n    \"tag\": "probiology",\n    \"popularity\": 1273003\n  },\n  {\n    \"tag\": "rhizomic",\n    \"popularity\": 1250308\n  },\n  {\n    \"tag\": "superphosphate",\n    \"popularity\": 1228240\n  },\n  {\n    \"tag\": "Hippolytan",\n    \"popularity\": 1206776\n  },\n  {\n    \"tag\": "garget",\n    \"popularity\": 1185892\n  },\n  {\n    \"tag\": "diploplacula",\n    \"popularity\": 1165568\n  },\n  {\n    \"tag\": "orohydrographical",\n    \"popularity\": 1145785\n  },\n  {\n    \"tag\": "enhypostatize",\n    \"popularity\": 1126521\n  },\n  {\n    \"tag\": "polisman",\n    \"popularity\": 1107759\n  },\n  {\n    \"tag\": "acetometer",\n    \"popularity\": 1089482\n  },\n  {\n    \"tag\": "unsnatched",\n    \"popularity\": 1071672\n  },\n  {\n    \"tag\": "yabber",\n    \"popularity\": 1054313\n  },\n  {\n    \"tag\": "demiwolf",\n    \"popularity\": 1037390\n  },\n  {\n    \"tag\": "chromascope",\n    \"popularity\": 1020888\n  },\n  {\n    \"tag\": "seamanship",\n    \"popularity\": 1004794\n  },\n  {\n    \"tag\": "nonfenestrated",\n    \"popularity\": 989092\n  },\n  {\n    \"tag\": "hydrophytism",\n    \"popularity\": 973771\n  },\n  {\n    \"tag\": "dotter",\n    \"popularity\": 958819\n  },\n  {\n    \"tag\": "thermoperiodism",\n    \"popularity\": 944222\n  },\n  {\n    \"tag\": "unlawyerlike",\n    \"popularity\": 929970\n  },\n  {\n    \"tag\": "enantiomeride citywards",\n    \"popularity\": 916052\n  },\n  {\n    \"tag\": "unmetallurgical",\n    \"popularity\": 902456\n  },\n  {\n    \"tag\": "prickled",\n    \"popularity\": 889174\n  },\n  {\n    \"tag\": "strangerwise manioc",\n    \"popularity\": 876195\n  },\n  {\n    \"tag\": "incisorial",\n    \"popularity\": 863510\n  },\n  {\n    \"tag\": "irrationalize",\n    \"popularity\": 851110\n  },\n  {\n    \"tag\": "nasology",\n    \"popularity\": 838987\n  },\n  {\n    \"tag\": "fatuism",\n    \"popularity\": 827131\n  },\n  {\n    \"tag\": "Huk",\n    \"popularity\": 815535\n  },\n  {\n    \"tag\": "properispomenon",\n    \"popularity\": 804192\n  },\n  {\n    \"tag\": "unpummelled",\n    \"popularity\": 793094\n  },\n  {\n    \"tag\": "technographically",\n    \"popularity\": 782233\n  },\n  {\n    \"tag\": "underfurnish",\n    \"popularity\": 771603\n  },\n  {\n    \"tag\": "sinter",\n    \"popularity\": 761198\n  },\n  {\n    \"tag\": "lateroanterior",\n    \"popularity\": 751010\n  },\n  {\n    \"tag\": "nonpersonification",\n    \"popularity\": 741034\n  },\n  {\n    \"tag\": "Sitophilus",\n    \"popularity\": 731264\n  },\n  {\n    \"tag\": "unstudded overexerted",\n    \"popularity\": 721694\n  },\n  {\n    \"tag\": "tracheation",\n    \"popularity\": 712318\n  },\n  {\n    \"tag\": "thirteenth begloze",\n    \"popularity\": 703131\n  },\n  {\n    \"tag\": "bespice",\n    \"popularity\": 694129\n  },\n  {\n    \"tag\": "doppia",\n    \"popularity\": 685305\n  },\n  {\n    \"tag\": "unadorned",\n    \"popularity\": 676656\n  },\n  {\n    \"tag\": "dovelet engraff",\n    \"popularity\": 668176\n  },\n  {\n    \"tag\": "diphyozooid",\n    \"popularity\": 659862\n  },\n  {\n    \"tag\": "mure",\n    \"popularity\": 651708\n  },\n  {\n    \"tag\": "Tripitaka",\n    \"popularity\": 643710\n  },\n  {\n    \"tag\": "Billjim",\n    \"popularity\": 635865\n  },\n  {\n    \"tag\": "pyramidical",\n    \"popularity\": 628169\n  },\n  {\n    \"tag\": "circumlocutionist",\n    \"popularity\": 620617\n  },\n  {\n    \"tag\": "slapstick",\n    \"popularity\": 613207\n  },\n  {\n    \"tag\": "preobedience",\n    \"popularity\": 605934\n  },\n  {\n    \"tag\": "unfriarlike",\n    \"popularity\": 598795\n  },\n  {\n    \"tag\": "microchromosome",\n    \"popularity\": 591786\n  },\n  {\n    \"tag\": "Orphicism",\n    \"popularity\": 584905\n  },\n  {\n    \"tag\": "peel",\n    \"popularity\": 578149\n  },\n  {\n    \"tag\": "obediential",\n    \"popularity\": 571514\n  },\n  {\n    \"tag\": "Peripatidea",\n    \"popularity\": 564997\n  },\n  {\n    \"tag\": "undoubtful",\n    \"popularity\": 558596\n  },\n  {\n    \"tag\": "lodgeable",\n    \"popularity\": 552307\n  },\n  {\n    \"tag\": "pustulated woodchat",\n    \"popularity\": 546129\n  },\n  {\n    \"tag\": "antepast",\n    \"popularity\": 540057\n  },\n  {\n    \"tag\": "sagittoid matrimoniously",\n    \"popularity\": 534091\n  },\n  {\n    \"tag\": "Albizzia",\n    \"popularity\": 528228\n  },\n  {\n    \"tag\": "Elateridae unnewness",\n    \"popularity\": 522464\n  },\n  {\n    \"tag\": "convertingness",\n    \"popularity\": 516798\n  },\n  {\n    \"tag\": "Pelew",\n    \"popularity\": 511228\n  },\n  {\n    \"tag\": "recapitulation",\n    \"popularity\": 505751\n  },\n  {\n    \"tag\": "shack",\n    \"popularity\": 500365\n  },\n  {\n    \"tag\": "unmellowed",\n    \"popularity\": 495069\n  },\n  {\n    \"tag\": "pavis capering",\n    \"popularity\": 489859\n  },\n  {\n    \"tag\": "fanfare",\n    \"popularity\": 484735\n  },\n  {\n    \"tag\": "sole",\n    \"popularity\": 479695\n  },\n  {\n    \"tag\": "subarcuate",\n    \"popularity\": 474735\n  },\n  {\n    \"tag\": "multivious",\n    \"popularity\": 469856\n  },\n  {\n    \"tag\": "squandermania",\n    \"popularity\": 465054\n  },\n  {\n    \"tag\": "scintle",\n    \"popularity\": 460329\n  },\n  {\n    \"tag\": "hash chirognomic",\n    \"popularity\": 455679\n  },\n  {\n    \"tag\": "linseed",\n    \"popularity\": 451101\n  },\n  {\n    \"tag\": "redoubtable",\n    \"popularity\": 446596\n  },\n  {\n    \"tag\": "poachy reimpact",\n    \"popularity\": 442160\n  },\n  {\n    \"tag\": "limestone",\n    \"popularity\": 437792\n  },\n  {\n    \"tag\": "serranid",\n    \"popularity\": 433492\n  },\n  {\n    \"tag\": "pohna",\n    \"popularity\": 429258\n  },\n  {\n    \"tag\": "warwolf",\n    \"popularity\": 425088\n  },\n  {\n    \"tag\": "ruthenous",\n    \"popularity\": 420981\n  },\n  {\n    \"tag\": "dover",\n    \"popularity\": 416935\n  },\n  {\n    \"tag\": "deuteroalbumose",\n    \"popularity\": 412950\n  },\n  {\n    \"tag\": "pseudoprophetic",\n    \"popularity\": 409025\n  },\n  {\n    \"tag\": "dissoluteness",\n    \"popularity\": 405157\n  },\n  {\n    \"tag\": "preinvention",\n    \"popularity\": 401347\n  },\n  {\n    \"tag\": "swagbellied",\n    \"popularity\": 397592\n  },\n  {\n    \"tag\": "Ophidia",\n    \"popularity\": 393892\n  },\n  {\n    \"tag\": "equanimity",\n    \"popularity\": 390245\n  },\n  {\n    \"tag\": "troutful",\n    \"popularity\": 386651\n  },\n  {\n    \"tag\": "uke",\n    \"popularity\": 383108\n  },\n  {\n    \"tag\": "preacquaint",\n    \"popularity\": 379616\n  },\n  {\n    \"tag\": "shoq",\n    \"popularity\": 376174\n  },\n  {\n    \"tag\": "yox",\n    \"popularity\": 372780\n  },\n  {\n    \"tag\": "unelemental",\n    \"popularity\": 369434\n  },\n  {\n    \"tag\": "Yavapai",\n    \"popularity\": 366134\n  },\n  {\n    \"tag\": "joulean",\n    \"popularity\": 362880\n  },\n  {\n    \"tag\": "dracontine",\n    \"popularity\": 359672\n  },\n  {\n    \"tag\": "hardmouth",\n    \"popularity\": 356507\n  },\n  {\n    \"tag\": "sylvanize",\n    \"popularity\": 353386\n  },\n  {\n    \"tag\": "intraparenchymatous meadowbur",\n    \"popularity\": 350308\n  },\n  {\n    \"tag\": "uncharily",\n    \"popularity\": 347271\n  },\n  {\n    \"tag\": "redtab flexibly",\n    \"popularity\": 344275\n  },\n  {\n    \"tag\": "centervelic",\n    \"popularity\": 341319\n  },\n  {\n    \"tag\": "unravellable",\n    \"popularity\": 338403\n  },\n  {\n    \"tag\": "infortunately",\n    \"popularity\": 335526\n  },\n  {\n    \"tag\": "cannel",\n    \"popularity\": 332687\n  },\n  {\n    \"tag\": "oxyblepsia",\n    \"popularity\": 329885\n  },\n  {\n    \"tag\": "Damon",\n    \"popularity\": 327120\n  },\n  {\n    \"tag\": "etherin",\n    \"popularity\": 324391\n  },\n  {\n    \"tag\": "luminal",\n    \"popularity\": 321697\n  },\n  {\n    \"tag\": "interrogatorily presbyte",\n    \"popularity\": 319038\n  },\n  {\n    \"tag\": "hemiclastic",\n    \"popularity\": 316414\n  },\n  {\n    \"tag\": "poh flush",\n    \"popularity\": 313823\n  },\n  {\n    \"tag\": "Psoroptes",\n    \"popularity\": 311265\n  },\n  {\n    \"tag\": "dispirit",\n    \"popularity\": 308740\n  },\n  {\n    \"tag\": "nashgab",\n    \"popularity\": 306246\n  },\n  {\n    \"tag\": "Aphidiinae",\n    \"popularity\": 303784\n  },\n  {\n    \"tag\": "rhapsody nonconstruction",\n    \"popularity\": 301353\n  },\n  {\n    \"tag\": "Osmond",\n    \"popularity\": 298952\n  },\n  {\n    \"tag\": "Leonis",\n    \"popularity\": 296581\n  },\n  {\n    \"tag\": "Lemnian",\n    \"popularity\": 294239\n  },\n  {\n    \"tag\": "acetonic gnathonic",\n    \"popularity\": 291926\n  },\n  {\n    \"tag\": "surculus",\n    \"popularity\": 289641\n  },\n  {\n    \"tag\": "diagonally",\n    \"popularity\": 287384\n  },\n  {\n    \"tag\": "counterpenalty",\n    \"popularity\": 285154\n  },\n  {\n    \"tag\": "Eugenie",\n    \"popularity\": 282952\n  },\n  {\n    \"tag\": "hornbook",\n    \"popularity\": 280776\n  },\n  {\n    \"tag\": "miscoin",\n    \"popularity\": 278626\n  },\n  {\n    \"tag\": "admi",\n    \"popularity\": 276501\n  },\n  {\n    \"tag\": "Tarmac",\n    \"popularity\": 274402\n  },\n  {\n    \"tag\": "inexplicable",\n    \"popularity\": 272328\n  },\n  {\n    \"tag\": "rascallion",\n    \"popularity\": 270278\n  },\n  {\n    \"tag\": "dusterman",\n    \"popularity\": 268252\n  },\n  {\n    \"tag\": "osteostomous unhoroscopic",\n    \"popularity\": 266250\n  },\n  {\n    \"tag\": "spinibulbar",\n    \"popularity\": 264271\n  },\n  {\n    \"tag\": "phototelegraphically",\n    \"popularity\": 262315\n  },\n  {\n    \"tag\": "Manihot",\n    \"popularity\": 260381\n  },\n  {\n    \"tag\": "neighborhood",\n    \"popularity\": 258470\n  },\n  {\n    \"tag\": "Vincetoxicum",\n    \"popularity\": 256581\n  },\n  {\n    \"tag\": "khirka",\n    \"popularity\": 254713\n  },\n  {\n    \"tag\": "conscriptive",\n    \"popularity\": 252866\n  },\n  {\n    \"tag\": "synechthran",\n    \"popularity\": 251040\n  },\n  {\n    \"tag\": "Guttiferales",\n    \"popularity\": 249235\n  },\n  {\n    \"tag\": "roomful",\n    \"popularity\": 247450\n  },\n  {\n    \"tag\": "germinal",\n    \"popularity\": 245685\n  },\n  {\n    \"tag\": "untraitorous",\n    \"popularity\": 243939\n  },\n  {\n    \"tag\": "nondissenting",\n    \"popularity\": 242213\n  },\n  {\n    \"tag\": "amotion",\n    \"popularity\": 240506\n  },\n  {\n    \"tag\": "badious",\n    \"popularity\": 238817\n  },\n  {\n    \"tag\": "sumpit",\n    \"popularity\": 237147\n  },\n  {\n    \"tag\": "ectozoic",\n    \"popularity\": 235496\n  },\n  {\n    \"tag\": "elvet",\n    \"popularity\": 233862\n  },\n  {\n    \"tag\": "underclerk",\n    \"popularity\": 232246\n  },\n  {\n    \"tag\": "reticency",\n    \"popularity\": 230647\n  },\n  {\n    \"tag\": "neutroclusion",\n    \"popularity\": 229065\n  },\n  {\n    \"tag\": "unbelieving",\n    \"popularity\": 227500\n  },\n  {\n    \"tag\": "histogenetic",\n    \"popularity\": 225952\n  },\n  {\n    \"tag\": "dermamyiasis",\n    \"popularity\": 224421\n  },\n  {\n    \"tag\": "telenergy",\n    \"popularity\": 222905\n  },\n  {\n    \"tag\": "axiomatic",\n    \"popularity\": 221406\n  },\n  {\n    \"tag\": "undominoed",\n    \"popularity\": 219922\n  },\n  {\n    \"tag\": "periosteoma",\n    \"popularity\": 218454\n  },\n  {\n    \"tag\": "justiciaryship",\n    \"popularity\": 217001\n  },\n  {\n    \"tag\": "autoluminescence",\n    \"popularity\": 215563\n  },\n  {\n    \"tag\": "osmous",\n    \"popularity\": 214140\n  },\n  {\n    \"tag\": "borgh",\n    \"popularity\": 212731\n  },\n  {\n    \"tag\": "bedebt",\n    \"popularity\": 211337\n  },\n  {\n    \"tag\": "considerableness adenoidism",\n    \"popularity\": 209957\n  },\n  {\n    \"tag\": "sailorizing",\n    \"popularity\": 208592\n  },\n  {\n    \"tag\": "Montauk",\n    \"popularity\": 207240\n  },\n  {\n    \"tag\": "Bridget",\n    \"popularity\": 205901\n  },\n  {\n    \"tag\": "Gekkota",\n    \"popularity\": 204577\n  },\n  {\n    \"tag\": "subcorymbose",\n    \"popularity\": 203265\n  },\n  {\n    \"tag\": "undersap",\n    \"popularity\": 201967\n  },\n  {\n    \"tag\": "poikilothermic",\n    \"popularity\": 200681\n  },\n  {\n    \"tag\": "enneatical",\n    \"popularity\": 199409\n  },\n  {\n    \"tag\": "martinetism",\n    \"popularity\": 198148\n  },\n  {\n    \"tag\": "sustanedly",\n    \"popularity\": 196901\n  },\n  {\n    \"tag\": "declaration",\n    \"popularity\": 195665\n  },\n  {\n    \"tag\": "myringoplasty",\n    \"popularity\": 194442\n  },\n  {\n    \"tag\": "Ginkgo",\n    \"popularity\": 193230\n  },\n  {\n    \"tag\": "unrecurrent",\n    \"popularity\": 192031\n  },\n  {\n    \"tag\": "proprecedent",\n    \"popularity\": 190843\n  },\n  {\n    \"tag\": "roadman",\n    \"popularity\": 189666\n  },\n  {\n    \"tag\": "elemin",\n    \"popularity\": 188501\n  },\n  {\n    \"tag\": "maggot",\n    \"popularity\": 187347\n  },\n  {\n    \"tag\": "alitrunk",\n    \"popularity\": 186204\n  },\n  {\n    \"tag\": "introspection",\n    \"popularity\": 185071\n  },\n  {\n    \"tag\": "batiker",\n    \"popularity\": 183950\n  },\n  {\n    \"tag\": "backhatch oversettle",\n    \"popularity\": 182839\n  },\n  {\n    \"tag\": "thresherman",\n    \"popularity\": 181738\n  },\n  {\n    \"tag\": "protemperance",\n    \"popularity\": 180648\n  },\n  {\n    \"tag\": "undern",\n    \"popularity\": 179568\n  },\n  {\n    \"tag\": "tweeg",\n    \"popularity\": 178498\n  },\n  {\n    \"tag\": "crosspath",\n    \"popularity\": 177438\n  },\n  {\n    \"tag\": "Tangaridae",\n    \"popularity\": 176388\n  },\n  {\n    \"tag\": "scrutation",\n    \"popularity\": 175348\n  },\n  {\n    \"tag\": "piecemaker",\n    \"popularity\": 174317\n  },\n  {\n    \"tag\": "paster",\n    \"popularity\": 173296\n  },\n  {\n    \"tag\": "unpretendingness",\n    \"popularity\": 172284\n  },\n  {\n    \"tag\": "inframundane",\n    \"popularity\": 171281\n  },\n  {\n    \"tag\": "kiblah",\n    \"popularity\": 170287\n  },\n  {\n    \"tag\": "playwrighting",\n    \"popularity\": 169302\n  },\n  {\n    \"tag\": "gonepoiesis snowslip",\n    \"popularity\": 168326\n  },\n  {\n    \"tag\": "hoodwise",\n    \"popularity\": 167359\n  },\n  {\n    \"tag\": "postseason",\n    \"popularity\": 166401\n  },\n  {\n    \"tag\": "equivocality",\n    \"popularity\": 165451\n  },\n  {\n    \"tag\": "Opiliaceae nuclease",\n    \"popularity\": 164509\n  },\n  {\n    \"tag\": "sextipara",\n    \"popularity\": 163576\n  },\n  {\n    \"tag\": "weeper",\n    \"popularity\": 162651\n  },\n  {\n    \"tag\": "frambesia",\n    \"popularity\": 161735\n  },\n  {\n    \"tag\": "answerable",\n    \"popularity\": 160826\n  },\n  {\n    \"tag\": "Trichosporum",\n    \"popularity\": 159925\n  },\n  {\n    \"tag\": "cajuputol",\n    \"popularity\": 159033\n  },\n  {\n    \"tag\": "pleomorphous",\n    \"popularity\": 158148\n  },\n  {\n    \"tag\": "aculeolate",\n    \"popularity\": 157270\n  },\n  {\n    \"tag\": "wherever",\n    \"popularity\": 156400\n  },\n  {\n    \"tag\": "collapse",\n    \"popularity\": 155538\n  },\n  {\n    \"tag\": "porky",\n    \"popularity\": 154683\n  },\n  {\n    \"tag\": "perule",\n    \"popularity\": 153836\n  },\n  {\n    \"tag\": "Nevada",\n    \"popularity\": 152996\n  },\n  {\n    \"tag\": "conalbumin",\n    \"popularity\": 152162\n  },\n  {\n    \"tag\": "tsunami",\n    \"popularity\": 151336\n  },\n  {\n    \"tag\": "Gulf",\n    \"popularity\": 150517\n  },\n  {\n    \"tag\": "hertz",\n    \"popularity\": 149705\n  },\n  {\n    \"tag\": "limmock",\n    \"popularity\": 148900\n  },\n  {\n    \"tag\": "Tartarize",\n    \"popularity\": 148101\n  },\n  {\n    \"tag\": "entosphenoid",\n    \"popularity\": 147310\n  },\n  {\n    \"tag\": "ibis",\n    \"popularity\": 146524\n  },\n  {\n    \"tag\": "unyeaned",\n    \"popularity\": 145746\n  },\n  {\n    \"tag\": "tritural",\n    \"popularity\": 144973\n  },\n  {\n    \"tag\": "hundredary",\n    \"popularity\": 144207\n  },\n  {\n    \"tag\": "stolonlike",\n    \"popularity\": 143448\n  },\n  {\n    \"tag\": "chorister",\n    \"popularity\": 142694\n  },\n  {\n    \"tag\": "mismove",\n    \"popularity\": 141947\n  },\n  {\n    \"tag\": "Andine",\n    \"popularity\": 141206\n  },\n  {\n    \"tag\": "Annette proneur escribe",\n    \"popularity\": 140471\n  },\n  {\n    \"tag\": "exoperidium",\n    \"popularity\": 139742\n  },\n  {\n    \"tag\": "disedge",\n    \"popularity\": 139019\n  },\n  {\n    \"tag\": "hypochloruria",\n    \"popularity\": 138302\n  },\n  {\n    \"tag\": "prepupa",\n    \"popularity\": 137590\n  },\n  {\n    \"tag\": "assent",\n    \"popularity\": 136884\n  },\n  {\n    \"tag\": "hydrazobenzene",\n    \"popularity\": 136184\n  },\n  {\n    \"tag\": "emballonurid",\n    \"popularity\": 135489\n  },\n  {\n    \"tag\": "roselle",\n    \"popularity\": 134800\n  },\n  {\n    \"tag\": "unifiedly",\n    \"popularity\": 134117\n  },\n  {\n    \"tag\": "clang",\n    \"popularity\": 133439\n  },\n  {\n    \"tag\": "acetolytic",\n    \"popularity\": 132766\n  },\n  {\n    \"tag\": "cladodont",\n    \"popularity\": 132098\n  },\n  {\n    \"tag\": "recoast",\n    \"popularity\": 131436\n  },\n  {\n    \"tag\": "celebrated tydie Eocarboniferous",\n    \"popularity\": 130779\n  },\n  {\n    \"tag\": "superconsciousness",\n    \"popularity\": 130127\n  },\n  {\n    \"tag\": "soberness",\n    \"popularity\": 129480\n  },\n  {\n    \"tag\": "panoramist",\n    \"popularity\": 128838\n  },\n  {\n    \"tag\": "Orbitolina",\n    \"popularity\": 128201\n  },\n  {\n    \"tag\": "overlewd",\n    \"popularity\": 127569\n  },\n  {\n    \"tag\": "demiquaver",\n    \"popularity\": 126942\n  },\n  {\n    \"tag\": "kamelaukion",\n    \"popularity\": 126319\n  },\n  {\n    \"tag\": "flancard",\n    \"popularity\": 125702\n  },\n  {\n    \"tag\": "tricuspid",\n    \"popularity\": 125089\n  },\n  {\n    \"tag\": "bepelt",\n    \"popularity\": 124480\n  },\n  {\n    \"tag\": "decuplet",\n    \"popularity\": 123877\n  },\n  {\n    \"tag\": "Rockies",\n    \"popularity\": 123278\n  },\n  {\n    \"tag\": "unforgeability",\n    \"popularity\": 122683\n  },\n  {\n    \"tag\": "mocha",\n    \"popularity\": 122093\n  },\n  {\n    \"tag\": "scrunge",\n    \"popularity\": 121507\n  },\n  {\n    \"tag\": "delighter",\n    \"popularity\": 120926\n  },\n  {\n    \"tag\": "willey Microtinae",\n    \"popularity\": 120349\n  },\n  {\n    \"tag\": "unhuntable",\n    \"popularity\": 119777\n  },\n  {\n    \"tag\": "historically",\n    \"popularity\": 119208\n  },\n  {\n    \"tag\": "vicegerentship",\n    \"popularity\": 118644\n  },\n  {\n    \"tag\": "hemangiosarcoma",\n    \"popularity\": 118084\n  },\n  {\n    \"tag\": "harpago",\n    \"popularity\": 117528\n  },\n  {\n    \"tag\": "unionoid",\n    \"popularity\": 116976\n  },\n  {\n    \"tag\": "wiseman",\n    \"popularity\": 116429\n  },\n  {\n    \"tag\": "diclinism",\n    \"popularity\": 115885\n  },\n  {\n    \"tag\": "Maud",\n    \"popularity\": 115345\n  },\n  {\n    \"tag\": "scaphocephalism",\n    \"popularity\": 114809\n  },\n  {\n    \"tag\": "obtenebration",\n    \"popularity\": 114277\n  },\n  {\n    \"tag\": "cymar predreadnought",\n    \"popularity\": 113749\n  },\n  {\n    \"tag\": "discommend",\n    \"popularity\": 113225\n  },\n  {\n    \"tag\": "crude",\n    \"popularity\": 112704\n  },\n  {\n    \"tag\": "upflash",\n    \"popularity\": 112187\n  }]';

var log2 = Math.log(2);
var tagInfo = tagInfoJSON.parseJSON(function(a, b) { if (a == "popularity") { return Math.log(b) / log2; } else {return b; } });

function makeTagCloud(tagInfo)
{
    var output = '<div class="tagCloud" style="width: 100%">';

    tagInfo.sort(function(a, b) { if (a.tag < b.tag) { return -1; } else if (a.tag == b.tag) { return 0; } else return 1; });

  /* BEGIN LOOP */
    for (var i = 0; i < tagInfo.length; i++) {
        var tag = tagInfo[i].tag;

        var validates = true;
  /* BEGIN LOOP */
        for (var j = 0; j < tag.length; j++) {
            var ch = tag.charCodeAt(j);
            if (ch < 0x20 || ch >= 0x7f) {
                validates = false;
                break;
            }
        }
  /* END LOOP */

        if (!validates)
            continue;

        var url = "http://example.com/tag/" + tag.replace(" ", "").toLowerCase();
        var popularity = tagInfo[i].popularity;
        var color = 'rgb(' + Math.floor(255 * (popularity - 12) / 20) + ', 0, 255)';
        output += ' <a href="' + url + '" style="font-size: ' + popularity + 'px; color: ' + color + '">' + tag + '</a> \n';
    }
  /* END LOOP */

    output += '</div>';
    output.replace(" ", "&nbsp;");

    return output;
}

var tagcloud = makeTagCloud(tagInfo);
tagInfo = null;
