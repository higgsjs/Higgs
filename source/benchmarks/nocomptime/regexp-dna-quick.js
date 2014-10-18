// The Computer Language Shootout
// http://shootout.alioth.debian.org/
//
// contributed by Jesse Millikan
// Base on the Ruby version by jose fco. gonzalez

var l;
var dnaInput = ">ONE Homo sapiens alu\n\
GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGGGAGGCCGAGGCGGGCGGA\n\
TCACCTGAGGTCAGGAGTTCGAGACCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACT\n\
AAAAATACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCAGCTACTCGGGAG\n\
GCTGAGGCAGGAGAATCGCTTGAACCCGGGAGGCGGAGGTTGCAGTGAGCCGAGATCGCG\n\
CCACTGCACTCCAGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAAGGCCGGGCGCGGT\n\
GGCTCACGCCTGTAATCCCAGCACTTTGGGAGGCCGAGGCGGGCGGATCACCTGAGGTCA\n\
GGAGTTCGAGACCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAATACAAAAA\n\
TTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCAGCTACTCGGGAGGCTGAGGCAGGAG\n\
AATCGCTTGAACCCGGGAGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCCA\n\
GCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAAGGCCGGGCGCGGTGGCTCACGCCTGT\n\
AATCCCAGCACTTTGGGAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGACC\n\
AGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAATACAAAAATTAGCCGGGCGTG\n\
GTGGCGCGCGCCTGTAATCCCAGCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACC\n\
CGGGAGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCCAGCCTGGGCGACAG\n\
AGCGAGACTCCGTCTCAAAAAGGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTT\n\
TGGGAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGACCAGCCTGGCCAACA\n\
";

dnaInput = dnaInput + dnaInput + dnaInput;

var ilen, clen,
 seqs = [
  /agggtaaa|tttaccct/ig,
  /[cgt]gggtaaa|tttaccc[acg]/ig,
  /a[act]ggtaaa|tttacc[agt]t/ig,
  /ag[act]gtaaa|tttac[agt]ct/ig,
  /agg[act]taaa|ttta[agt]cct/ig,
  /aggg[acg]aaa|ttt[cgt]ccct/ig,
  /agggt[cgt]aa|tt[acg]accct/ig,
  /agggta[cgt]a|t[acg]taccct/ig,
  /agggtaa[cgt]|[acg]ttaccct/ig],
 subs = {
  B: '(c|g|t)', D: '(a|g|t)', H: '(a|c|t)', K: '(g|t)',
  M: '(a|c)', N: '(a|c|g|t)', R: '(a|g)', S: '(c|t)',
  V: '(a|c|g)', W: '(a|t)', Y: '(c|t)' }

ilen = dnaInput.length;

// There is no in-place substitution
dnaInput = dnaInput.replace(/>.*\n|\n/g,"")
clen = dnaInput.length

var dnaOutputString;

  /* BEGIN LOOP */
for(i in seqs)
    dnaOutputString += seqs[i].source + " " + (dnaInput.match(seqs[i]) || []).length + "\n";
  /* END LOOP */
 // match returns null if no matches, so replace with empty

  /* BEGIN LOOP */
for(k in subs)
 dnaInput = dnaInput.replace(k, subs[k], "g")
  /* END LOOP */
 // search string, replacement string, flags
