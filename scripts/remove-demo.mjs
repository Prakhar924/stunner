/** Removes every account whose profile is marked is_test=true. */
const url = process.env.SUPABASE_URL?.replace(/\/$/, "");
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) throw new Error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first.");
const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" };
const response = await fetch(`${url}/rest/v1/profiles?is_test=eq.true&select=id`, { headers });
if (!response.ok) throw new Error(await response.text());
const profiles = await response.json();
for (const { id } of profiles) {
  const deleted = await fetch(`${url}/auth/v1/admin/users/${id}`, { method: "DELETE", headers });
  if (!deleted.ok) throw new Error(`${id}: ${await deleted.text()}`);
}
console.log(`Removed ${profiles.length} demo accounts.`);
