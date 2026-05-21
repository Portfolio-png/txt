const fs = require('fs');
const path = require('path');
const { initDb, closeDb, all, generateInvoicePdf, listInvoices } = require('../server.js');

async function main() {
  console.log('Initializing database...');
  await initDb();

  try {
    console.log('Listing invoices...');
    const invoices = await listInvoices();
    console.log(`Found ${invoices.length} invoices.`);

    if (invoices.length === 0) {
      console.log('No invoices found in database. Please run simulate-user-flow.js first.');
      return;
    }

    const invoice = invoices[0];
    const invoiceId = invoice.id;
    console.log(`Generating PDF for Invoice ID: ${invoiceId} (No: ${invoice.invoiceNo})...`);

    const pdfBuffer = await generateInvoicePdf(invoiceId);
    const outputPath = path.join(__dirname, '..', 'test-output.pdf');
    fs.writeFileSync(outputPath, pdfBuffer);
    console.log(`Success! PDF saved to ${outputPath}`);
  } catch (error) {
    console.error('Error generating PDF:', error);
  } finally {
    console.log('Closing database...');
    await closeDb();
  }
}

main().catch(console.error);
