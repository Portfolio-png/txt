const fs = require('fs');
const path = require('path');
const { 
  initDb, 
  closeDb, 
  all, 
  get, 
  createInvoice, 
  generateInvoicePdf 
} = require('../server.js');

async function main() {
  console.log('Initializing database...');
  await initDb();

  try {
    // 1. Get West Coast Printers client
    const client = await get("SELECT * FROM clients WHERE name = 'West Coast Printers'");
    if (!client) {
      console.log('Client "West Coast Printers" not found. Please run simulate-user-flow.js first.');
      return;
    }
    console.log(`Found client: ${client.name} (ID: ${client.id})`);

    // 2. Find issued delivery challans for this client
    const challans = await all(
      "SELECT * FROM delivery_challans WHERE type = 'delivery' AND customer_name = ? AND status = 'issued'",
      [client.name]
    );
    console.log(`Found ${challans.length} issued delivery challans.`);
    if (challans.length === 0) {
      console.log('No issued delivery challans found. Please run simulate-user-flow.js first.');
      return;
    }

    // 3. For each challan, get its items to construct the invoice lines
    const invoiceLines = [];
    for (const challan of challans) {
      const items = await all(
        "SELECT * FROM delivery_challan_items WHERE challan_id = ?",
        [challan.id]
      );
      for (const item of items) {
        invoiceLines.push({
          orderId: item.order_item_id, // order ID reference
          challanId: challan.id,
          challanItemId: item.id,
          itemId: item.item_id,
          variationLeafNodeId: item.variation_leaf_node_id || 0,
          itemName: item.particulars,
          hsnCode: item.hsn_code || '4802',
          quantity: item.quantity_pcs,
          unitPrice: 120.0, // standard price from order
          cgstRate: 9.0,    // 9% CGST
          sgstRate: 9.0,    // 9% SGST
        });
      }
    }

    // 4. Create invoice
    console.log(`Creating invoice with ${invoiceLines.length} lines...`);
    const invoice = await createInvoice({
      clientId: client.id,
      clientName: client.name,
      gstin: client.gst_number || '27AAAAA1111A1Z1',
      status: 'draft',
      lines: invoiceLines
    });

    console.log(`Successfully created Invoice ID: ${invoice.id} (No: ${invoice.invoice_no})`);

    // 5. Generate and save PDF
    console.log('Generating PDF...');
    const pdfBuffer = await generateInvoicePdf(invoice.id);
    const outputPath = path.join(__dirname, '..', 'test-output.pdf');
    fs.writeFileSync(outputPath, pdfBuffer);
    console.log(`Success! PDF saved to ${outputPath}`);

  } catch (error) {
    console.error('Error during test invoice flow:', error);
  } finally {
    console.log('Closing database...');
    await closeDb();
  }
}

main().catch(console.error);
