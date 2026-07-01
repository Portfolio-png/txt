async function cancel() {
  await fetch('http://localhost:18080/api/delivery-challans/10', { method: 'DELETE' });
  await fetch('http://localhost:18080/api/delivery-challans/11', { method: 'DELETE' });
  console.log("Deleted challans 10 and 11");
}
cancel();
