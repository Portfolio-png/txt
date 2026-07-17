async function rowToUploadedAssetDto(row, includeReadUrls = true) {
  if (!row) return null;
  const payload = includeReadUrls ? "payload_true" : "payload_false";
  return {row, payload};
}

async function rowToDeliveryChallanDto() {
  const assetRows = [1, 2, 3];
  try {
    const assets = await Promise.all(assetRows.map(rowToUploadedAssetDto));
    console.log(assets);
  } catch (err) {
    console.error(err);
  }
}
rowToDeliveryChallanDto();
