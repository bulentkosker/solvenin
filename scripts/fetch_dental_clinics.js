#!/usr/bin/env node
/* fetch_dental_clinics.js
   Fetches dental clinics from 2GIS Places API for Almaty and Astana.
   Test run — checks data quality + counts.
   Output: data/dental_clinics_test.json

   Usage:  node scripts/fetch_dental_clinics.js
*/

const fs   = require('fs');
const path = require('path');

const API_KEY   = 'b4f37320-ec48-4d34-89f7-4027cb62693d';
const BASE_URL  = 'https://catalog.api.2gis.com/3.0/items';
// 2GIS Places API caps page_size at 10 (spec value 50 returns
// 'paramIsOutsideSet'). Verified empirically.
const PAGE_SIZE = 10;
const DELAY_MS  = 700;
const FIELDS    = [
  'items.point',
  'items.address',
  'items.contact_groups',
  'items.schedule',
  'items.reviews',
  'items.rubrics',
  'items.links',
].join(',');

// NOTE: spec listed region_ids 141/147 but those are invalid in 2GIS.
// Verified via /2.0/region/search: Almaty=67, Astana=68.
const cities = [
  { name: 'Almaty', region_id: '67' },
  { name: 'Astana', region_id: '68' },
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function buildUrl(regionId, page) {
  const params = new URLSearchParams({
    q:          'стоматология',
    region_id:  regionId,
    type:       'branch',
    page_size:  String(PAGE_SIZE),
    page:       String(page),
    fields:     FIELDS,
    locale:     'ru_KZ',
    key:        API_KEY,
  });
  return `${BASE_URL}?${params.toString()}`;
}

function extractClinic(item, cityName) {
  // Real 2GIS field shapes (verified empirically — they differ from spec):
  //   address: {building_code, components[], postcode}  ← no .name
  //   address_name: "улица Розыбакиева, 37в"            ← top-level
  //   reviews: {general_rating, general_review_count, org_rating, org_review_count}
  //   schedule: {Mon: {working_hours: [{from,to}]}, ..., is_24x7}
  //   contact_groups: NOT returned with this API key tier (always undefined)
  const contacts = item.contact_groups?.[0]?.contacts || [];
  const phone    = contacts.find((c) => c.type === 'phone')?.value || null;
  const website  = contacts.find((c) => c.type === 'website')?.value || null;

  // Build a compact "working_hours" summary from the schedule object.
  let workingHours = null;
  if (item.schedule?.is_24x7) {
    workingHours = '24/7';
  } else if (item.schedule) {
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const parts = days
      .map((d) => {
        const wh = item.schedule[d]?.working_hours;
        if (!wh || wh.length === 0) return `${d}:closed`;
        return `${d}:${wh.map((w) => `${w.from}-${w.to}`).join(',')}`;
      });
    workingHours = parts.join(' ');
  }

  return {
    id:             item.id,
    name:           item.name,
    city:           cityName,
    address:        item.address_name || null,
    lat:            item.point?.lat ?? null,
    lon:            item.point?.lon ?? null,
    phone:          phone,
    website:        website,
    rating:         item.reviews?.org_rating ?? item.reviews?.general_rating ?? null,
    reviews_count:  item.reviews?.org_review_count ?? item.reviews?.general_review_count ?? null,
    working_hours:  workingHours,
  };
}

async function fetchPage(url) {
  const res = await fetch(url);
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`HTTP ${res.status} — ${text.slice(0, 200)}`);
  }
  return res.json();
}

async function fetchCity(city, stats) {
  console.log(`\n[${city.name}] (region_id=${city.region_id}) fetching...`);
  const out = [];
  let   page = 1;
  let   total = null;

  while (true) {
    const url = buildUrl(city.region_id, page);
    let json;
    try {
      json = await fetchPage(url);
      stats.requests += 1;
    } catch (e) {
      console.error(`  page ${page} error:`, e.message);
      break;
    }

    const items     = json?.result?.items || [];
    const reported  = json?.result?.total ?? null;
    if (total === null && reported !== null) total = reported;

    console.log(
      `  page ${page}: +${items.length} items` +
      (total !== null ? ` (reported total: ${total})` : '')
    );

    if (items.length === 0) break;

    for (const item of items) out.push(extractClinic(item, city.name));

    if (items.length < PAGE_SIZE) break;
    if (total !== null && out.length >= total) break;

    page += 1;
    await sleep(DELAY_MS);
  }

  console.log(`[${city.name}] done — ${out.length} clinics`);
  return out;
}

(async () => {
  const stats   = { requests: 0 };
  const all     = [];
  const perCity = {};

  for (const city of cities) {
    const clinics = await fetchCity(city, stats);
    perCity[city.name] = clinics.length;
    all.push(...clinics);
    await sleep(DELAY_MS);
  }

  const outPath = path.join(__dirname, '..', 'data', 'dental_clinics_test.json');
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(all, null, 2), 'utf8');

  console.log('\n========== SUMMARY ==========');
  for (const [name, count] of Object.entries(perCity)) {
    console.log(`  ${name}: ${count} clinics`);
  }
  console.log(`  Total: ${all.length} clinics`);
  console.log(`  Total API requests used: ${stats.requests}`);
  console.log(`  Saved to: ${path.relative(process.cwd(), outPath)}`);
})().catch((e) => {
  console.error('FATAL:', e);
  process.exit(1);
});
