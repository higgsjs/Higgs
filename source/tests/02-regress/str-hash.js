// Regression for issue in PR #171 where the hash is computed only
// on the first half of strings

function test()
{
    var strs = [
        'aaaabbbb',
        'aaaacccc',
        'aaaadddd',
        'aaaaeeee',
    ];

    var h0 = $rt_str_get_hash(strs[0]);

    for (var i = 1; i < strs.length; ++i)
    {
        var hI = $rt_str_get_hash(strs[i]);

        // If string hashes differ, we pass the test
        if (h0 !== hI)
            return;
    }

    throw Error('string hashes all equal');
}

test();
