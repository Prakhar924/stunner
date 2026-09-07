/**
 * Creates clearly labelled, non-production demo accounts.
 * Requires Node 18+ and SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.
 */

const url = process.env.SUPABASE_URL?.replace(/\/$/, "");
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const count = Math.min(1000, Math.max(1, Number(process.env.DEMO_ACCOUNT_COUNT || 1000)));

if (!url || !serviceKey) {
  throw new Error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY before running this script.");
}

const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" };
const names = ["Aanya","Aarohi","Aditi","Anika","Avni","Diya","Ira","Ishita","Kavya","Kiara","Meera","Mira","Myra","Navya","Niharika","Rhea","Saanvi","Sara","Tara","Vanya"];
const interests = ["Chai walks","Indie films","Street food","Live music","Books","Badminton","Photography","Travel","Cooking","Dogs","Art","Running"];
const bios = [
  "Demo profile for testing discovery, matching and moderation flows.",
  "Synthetic account created for staging and product QA only.",
  "Fictional test profile — here to help the Stunner team test safely."
];

function sample(list, offset) { return list[offset % list.length]; }
function passwordFor(i) {
  return `Demo-${crypto.randomUUID()}-${i}!Aa9`;
}
async function request(path, options = {}) {
  const response = await fetch(`${url}${path}`, { ...options, headers: { ...headers, ...options.headers } });
  const body = await response.text();
  if (!response.ok) throw new Error(`${response.status} ${path}: ${body}`);
  return body ? JSON.parse(body) : null;
}

async function createOne(i) {
  const n = i + 1;
  const serial = String(n).padStart(4, "0");
  const email = `stunner-demo-${serial}@example.invalid`;
  const authUser = await request("/auth/v1/admin/users", {
    method: "POST",
    body: JSON.stringify({ email, password: passwordFor(n), email_confirm: true, user_metadata: { demo_account: true } })
  });

  const birthYear = 1990 + (n % 14);
  const profile = {
    id: authUser.id,
    name: `[DEMO] ${sample(names, n)} ${serial}`,
    dob: `${birthYear}-${String((n % 12) + 1).padStart(2,"0")}-${String((n % 27) + 1).padStart(2,"0")}`,
    gender: "woman",
    interested_in: n % 5 === 0 ? "everyone" : "men",
    city: "Delhi",
    bio: sample(bios, n),
    job_title: ["Designer","Teacher","Consultant","Engineer","Founder"][n % 5],
    education: ["Delhi University","JNU","Ambedkar University Delhi","Jamia Millia Islamia"][n % 4],
    photos: [`https://api.dicebear.com/9.x/shapes/svg?seed=stunner-${serial}&backgroundColor=f2a93b,d6336c,0e6b63`],
    status: "verified",
    dating_intention: ["relationship","casual","figuring_out","friendship"][n % 4],
    interests: [sample(interests,n), sample(interests,n+3), sample(interests,n+7)],
    prompt_key: "first_date",
    prompt_answer: "Testing a safe, respectful conversation starter.",
    opening_move: ["What's your favourite Delhi food spot?","Window seat or aisle seat?","What song is on repeat for you?"][n % 3],
    is_test: true
  };
  try {
    await request("/rest/v1/profiles", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify(profile) });
  } catch (error) {
    await fetch(`${url}/auth/v1/admin/users/${authUser.id}`, { method: "DELETE", headers });
    throw error;
  }
  return n;
}

for (let start = 0; start < count; start += 10) {
  const batch = Array.from({ length: Math.min(10, count - start) }, (_, j) => createOne(start + j));
  await Promise.all(batch);
  console.log(`Created ${Math.min(start + 10, count)} / ${count} demo accounts`);
}

console.log("Done. Demo accounts are marked is_test=true and excluded from real discovery.");
