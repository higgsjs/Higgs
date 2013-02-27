echo "$*" > /tmp/test.s
echo "32-bit Encoding"
nasm -o /dev/null -f elf32 -O2 -l /tmp/test.txt /tmp/test.s
cat /tmp/test.txt
echo "64-bit Encoding"
nasm -o /dev/null -f elf64 -O2 -l /tmp/test.txt /tmp/test.s
cat /tmp/test.txt
