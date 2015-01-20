var csv = require('lib/csv');

var stdio = require('lib/stdio');

// Create a new CSV spreadsheet object
sheet = new csv.CSV();

// Data can be added to the spread sheet row by row
sheet.addRow(['name', 'age', 'sex']);
sheet.addRow(['Alice', '19', 'F']);
sheet.addRow(['Bob', '22', 'M']);
sheet.addRow(['Kirby', '1', 'N/A']);

// You can set individual cell values directly using the setCell method
// This will change Alice's name to Anna:
sheet.setCell(1, 0, 'Anna');

// Rows can also be directly addressed with the setRow method
// This replaces the last row:
sheet.setRow(3, ['John', '35', 'M']);

// Write the data to a CSV file
tmpName = stdio.tmpname();
sheet.writeFile(tmpName);

// Read a spreadsheet from a CSV file
sheet = csv.readFile(tmpName);

assert(sheet.getNumRows() === 4, 'failed to read all rows');

assert (sheet.getCell(3, 0) === 'John');

