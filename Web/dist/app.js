const paths = {
  home: "m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z",
  chat: "M21 11.5a8.5 8.5 0 0 1-8.5 8.5H4l-3 2 1.5-6A8.5 8.5 0 1 1 21 11.5Z",
  settings:
    "m9 3 1-2h4l1 2 2 1 2-.2 2 3-1 2v3l1 2-2 3-2-.2-2 1-1 2h-4l-1-2-2-1-2 .2-2-3 1-2v-3l-1-2 2-3 2 .2Z M15 10a3 3 0 1 1-6 0 3 3 0 0 1 6 0",
  user: "M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0 M4 21v-2a8 8 0 0 1 16 0v2",
  search: "M20 20l-5-5 M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0",
  plus: "M12 5v14 M5 12h14",
  down: "m8 10 4 4 4-4",
  arrow: "M5 12h14 m-5-5 5 5-5 5",
  bell: "M18 8a6 6 0 0 0-12 0c0 8-3 8-3 9h18c0-1-3-1-3-9 M10 21h4",
  heart:
    "M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z",
  bookmark: "M6 3h12v18l-6-4-6 4Z",
  image:
    "M4 3h16a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z m-1 14 6-6 4 4 3-3 5 5 M16 7h.01",
  lock: "M6 10h12v11H6Z M8 10V6a4 4 0 0 1 8 0v4",
  more: "M5 12h.01 M12 12h.01 M19 12h.01",
  people:
    "M15 8a3 3 0 1 1-6 0 3 3 0 0 1 6 0 M5 21v-2a7 7 0 0 1 14 0v2 M18 3a3 3 0 0 1 0 6 M20 13a5 5 0 0 1 3 5 M6 3a3 3 0 0 0 0 6 M4 13a5 5 0 0 0-3 5",
  smile:
    "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0 M8 9h.01 M16 9h.01 M7 14q5 7 10 0",
  close: "m6 6 12 12 M6 18 18 6",
  send: "m22 2-7 20-4-9L2 9Z M22 2 11 13",
  check: "m5 12 4 4L19 6",
  location:
    "M19 9c0 5-7 12-7 12S5 14 5 9a7 7 0 0 1 14 0 M14 9a2 2 0 1 1-4 0 2 2 0 0 1 4 0",
  globe:
    "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0 M2 12h20 M12 2q-8 10 0 20 M12 2q8 10 0 20",
  shield: "m12 2 9 4v6c0 5-9 10-9 10S3 17 3 12V6Z m-5 10 3 3 5-6",
  log: "M4 4h16v16H4Z M8 9h8 M8 13h5",
  moon: "M21 13A9 9 0 0 1 11 3a9 9 0 1 0 10 10",
  edit: "m15 4 5 5 M4 20l5-1L21 7l-5-5L4 14Z",
  coffee:
    "M4 8h13v8a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5Z M17 8h3a3 3 0 0 1 0 6h-3 M7 1v3 M12 1v3",
};
const icon = (name) =>
  `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name] || paths.smile}"/></svg>`;
const esc = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const people = [
  { id: "alex", name: "Alex", status: "Probably out exploring", online: true },
  { id: "mia", name: "Mia", status: "One more coffee ☕", online: true },
  { id: "radu", name: "Radu", status: "Making a playlist", online: true },
  { id: "sofia", name: "Sofia", status: "See you this weekend", online: false },
  { id: "teo", name: "Teo", status: "Taking the scenic route", online: false },
];
const initial = () => ({
  version: 1,
  profile: {
    name: "Lamaie",
    bio: "Good people. Unplanned adventures. A little bit of everything.",
    location: "Bucharest, Romania",
  },
  theme: "aurora",
  consent: true,
  sounds: false,
  notifications: true,
  circle: "The inner circle",
  posts: [
    {
      id: "coast",
      person: "alex",
      text: "No plans, just the scenic route. Pretty good way to spend a Sunday. 🌿",
      image: "assets/coast.jpg",
      location: "Somewhere worth the detour",
      time: "2 hours ago",
      likes: 12,
      liked: false,
      saved: false,
      comments: [
        { name: "Mia", text: "Okay, adding this to the list 👀" },
        { name: "Radu", text: "Next time we’re coming too!" },
      ],
    },
    {
      id: "coffee",
      person: "mia",
      text: "A gentle reminder that “let’s grab a coffee” is a perfectly valid plan for the entire day. ☕",
      time: "4 hours ago",
      likes: 8,
      liked: false,
      saved: false,
      comments: [],
    },
    {
      id: "mountain",
      person: "radu",
      text: "Worth the early alarm. Same time next weekend?",
      image: "assets/mountain.jpg",
      location: "Out of office",
      time: "Yesterday",
      likes: 19,
      liked: false,
      saved: false,
      comments: [{ name: "Alex", text: "I’m in." }],
    },
  ],
  wall: [
    {
      id: "w1",
      text: "“I’ll be ready in 5 minutes”\n\n— someone who is still in bed",
      laughs: 8,
      liked: false,
    },
    {
      id: "w2",
      image: "assets/city.jpg",
      text: "The group chat at 2 am",
      laughs: 12,
      liked: false,
    },
    {
      id: "w3",
      text: "Our plans have more plot twists than a Netflix series.",
      laughs: 6,
      liked: false,
    },
  ],
  chats: {
    circle: [
      {
        text: "Sunday adventure? I found a great spot 👀",
        mine: false,
        time: "10:32",
        name: "Alex",
      },
      {
        text: "If there’s coffee, I’m in.",
        mine: false,
        time: "10:34",
        name: "Mia",
      },
      {
        text: "That’s all the convincing I needed.",
        mine: true,
        time: "10:35",
      },
    ],
    alex: [
      {
        text: "Hey! Sending the photos from our trip later 📸",
        mine: false,
        time: "11:42",
        name: "Alex",
      },
    ],
    mia: [
      { text: "Coffee tomorrow?", mine: false, time: "09:18", name: "Mia" },
    ],
    radu: [
      {
        text: "You need to hear this new playlist.",
        mine: false,
        time: "Yesterday",
        name: "Radu",
      },
    ],
  },
  stories: [],
});
const STORAGE = "loop-desktop-demo-v1";
let state;
try {
  const saved = JSON.parse(localStorage.getItem(STORAGE));
  state =
    saved?.version === 1 &&
    Array.isArray(saved.posts) &&
    saved.profile &&
    saved.chats &&
    Array.isArray(saved.wall) &&
    Array.isArray(saved.stories)
      ? saved
      : initial();
} catch {
  state = initial();
}
let page = "home",
  tab = "feed",
  selectedChat = "circle",
  query = "",
  chatQuery = "",
  sort = "recent";
const app = document.querySelector("#app");
const modal = document.querySelector("#modal");
let toastTimer;
function toast(message) {
  const el = document.querySelector("#toast");
  el.textContent = message;
  el.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), 3500);
}
function persist() {
  try {
    localStorage.setItem(STORAGE, JSON.stringify(state));
    return true;
  } catch {
    toast(
      "Browser storage is full. This change is available until you refresh.",
    );
    return false;
  }
}
function person(id) {
  return id === "me"
    ? { id: "me", name: state.profile.name }
    : people.find((p) => p.id === id) || people[0];
}
function avatar(id, classes = "") {
  const p = person(id);
  return `<span class="avatar ${classes}">${id === "me" ? esc(state.profile.name.slice(0, 1).toUpperCase()) : `<img src="assets/${p.id}.jpg" alt="" loading="lazy">`}</span>`;
}
function buttonIcon(name, label, action, extra = "") {
  return `<button class="icon-button ${extra}" aria-label="${esc(label)}" title="${esc(label)}" data-action="${action}">${icon(name)}</button>`;
}
function render() {
  document.body.dataset.theme = state.theme;
  const names = {
    home: "Home",
    chats: "Messages",
    settings: "Settings",
    profile: "Profile",
    search: "Search",
  };
  app.innerHTML = `<aside class="sidebar"><a class="brand" href="#home" aria-label="Loop home"><img src="assets/loop.png" alt=""><span>loop</span></a><div class="workspace-label">YOUR SPACE</div><button class="circle-select" data-action="circle"><span class="circle-icon">${icon("people")}</span><span class="grow stack"><strong style="font-size:12px">${esc(state.circle)}</strong><small>6 people, one loop</small></span>${icon("down")}</button><nav class="nav" aria-label="Main navigation">${[
    ["home", "home", "Home"],
    ["chats", "chat", "Chats"],
    ["settings", "settings", "Settings"],
    ["profile", "user", "Profile"],
  ]
    .map(
      ([id, i, n]) =>
        `<button data-page="${id}" class="${page === id ? "active" : ""}" ${page === id ? 'aria-current="page"' : ""}>${icon(i)}<span>${n}</span>${id === "chats" ? '<span class="count">3</span>' : ""}</button>`,
    )
    .join(
      "",
    )}</nav><div class="sidebar-bottom"><div class="sidebar-note">${icon("lock")}<p>A little space.<br>Just for your people.</p></div><button class="sidebar-user row" data-page="profile">${avatar("me", "online")}<span class="grow stack"><strong style="font-size:12px">${esc(state.profile.name)}</strong><small>Your personal space</small></span>${icon("more")}</button></div></aside><main class="shell"><header class="topbar"><div class="breadcrumb">Your space <span>/</span><span>${names[page]}</span></div><a class="mobile-brand" href="#home"><img src="assets/loop.png" alt="">loop</a><div class="top-actions"><form id="search-form" class="search" role="search">${icon("search")}<input name="q" aria-label="Search Loop" placeholder="Search your loop" value="${esc(query)}"><kbd>Ctrl K</kbd></form>${buttonIcon("bell", "Recent activity", "notifications", "notification")}<button class="icon-button" data-page="profile" aria-label="Your profile">${avatar("me", "sm")}</button></div></header>${page === "home" ? home() : page === "chats" ? chats() : page === "settings" ? settings() : page === "profile" ? profile() : searchPage()}</main>`;
  if (page === "chats") scrollMessages();
}
function heading(title, subtitle, action = "", label = "New post", i = "plus") {
  return `<div class="page-heading"><div><h1>${title}</h1><p>${subtitle}</p></div>${action ? `<button class="primary" data-action="${action}">${icon(i)}<span>${label}</span></button>` : '<span class="local-label">LOCAL PREVIEW</span>'}</div>`;
}
function home() {
  return `${heading("Your people. Your space.", "The little moments that keep you close.", tab === "wall" ? "anonymous" : "compose", tab === "wall" ? "Post anonymously" : "New post")}<div class="layout"><section class="feed-column" aria-label="Circle feed"><div class="stories"><button class="story story-add" data-action="add-story"><span class="story-ring">${avatar("me")}<span class="plus">+</span></span><span>Your story</span></button>${people.map((p) => `<button class="story" data-story="${p.id}"><span class="story-ring">${avatar(p.id)}</span><span>${p.name}</span></button>`).join("")}${state.stories.length ? `<button class="story" data-story="mine"><span class="story-ring">${avatar("me")}</span><span>Your moments</span></button>` : ""}</div><div class="tabs-row"><div class="tabs" role="tablist" aria-label="Feed type"><button role="tab" aria-selected="${tab === "feed"}" class="${tab === "feed" ? "active" : ""}" data-tab="feed">${icon("home")}Feed</button><button role="tab" aria-selected="${tab === "wall"}" class="${tab === "wall" ? "active" : ""}" data-tab="wall">${icon("smile")}Troll Wall</button></div><select class="sort" aria-label="Sort posts"><option value="recent" ${sort === "recent" ? "selected" : ""}>Most recent</option><option value="popular" ${sort === "popular" ? "selected" : ""}>Most loved</option></select></div>${tab === "feed" ? `<div class="composer">${avatar("me")}<button class="prompt" data-action="compose">What’s happening in your world?</button>${buttonIcon("image", "Add a photo", "compose")}</div><div>${(sort === "popular" ? [...state.posts].sort((a, b) => b.likes - a.likes) : state.posts).map(post).join("")}</div><p class="end-note">${icon("check")}<br>You’re all caught up. Go make a memory.</p>` : wall()}</section>${rail()}</div>`;
}
function post(p) {
  const author = person(p.person);
  return `<article class="post"><header class="post-header">${avatar(p.person)}<div class="grow"><h3>${esc(author.name)} ${p.person === "me" ? "<small>you</small>" : ""}</h3><small>${esc(p.time)}<span class="dot">·</span>${icon("people").replace("<svg", '<svg style="width:11px;height:11px;vertical-align:-2px"')} Your circle</small></div><button class="icon-button" aria-label="Post options" data-options="${p.id}">${icon("more")}</button></header>${p.text ? `<p class="post-copy">${esc(p.text).replace(/\n/g, "<br>")}</p>` : ""}${p.image ? `<div class="photo-wrap"><img class="post-media" src="${esc(p.image)}" alt="${esc(p.location || "Photo shared with the circle")}" ${p.id === "coast" ? 'fetchpriority="high"' : 'loading="lazy"'}>${p.location ? `<span class="photo-tag">${icon("location")}${esc(p.location)}</span>` : ""}</div>` : ""}<footer class="post-actions"><button data-like="${p.id}" class="${p.liked ? "liked" : ""}" aria-label="${p.liked ? "Unlike" : "Like"} post" aria-pressed="${p.liked}">${icon("heart")}${p.likes}</button><button data-comments="${p.id}" aria-label="View comments">${icon("chat")}${p.comments.length}<span>comments</span></button><button class="save ${p.saved ? "liked" : ""}" aria-label="${p.saved ? "Unsave" : "Save"} post" aria-pressed="${p.saved}" data-save="${p.id}">${icon("bookmark")}</button></footer>${p.likes > 0 ? '<p class="liked-by">A little love from <strong>your people</strong></p>' : ""}</article>`;
}
function rail() {
  return `<aside class="rail"><section class="rail-card"><div class="rail-title"><h2>Your circle</h2>${icon("lock").replace("<svg", '<svg style="width:14px;height:14px;color:var(--faint)"')}</div><div class="circle-art"><div class="orbit"></div><div class="orbit two"></div><span class="circle-core">${icon("people")}</span>${avatar("mia")}${avatar("alex")}</div><div class="circle-description"><h3>${esc(state.circle)}</h3><p>Life’s better with your kind of people.</p></div><div class="member-pile">${people
    .slice(0, 4)
    .map((p) => avatar(p.id))
    .join(
      "",
    )}<span class="avatar">+2</span></div><button class="secondary wide" data-action="circle">View circle ${icon("arrow").replace("<svg", '<svg style="width:14px;height:14px"')}</button></section><section><div class="rail-title"><h2>In the loop</h2><span class="tiny"><i class="green-dot"></i>3 around</span></div>${people
    .slice(0, 4)
    .map(
      (p) =>
        `<button class="friend" data-chat="${p.id}">${avatar(p.id, p.online ? "online" : "")}<span class="grow stack"><strong>${p.name}</strong><small>${p.status}</small></span>${icon("chat")}</button>`,
    )
    .join(
      "",
    )}<button class="text-button" data-page="chats">Open messages ${icon("arrow").replace("<svg", '<svg style="width:13px;height:13px;vertical-align:middle;margin-left:4px"')}</button></section><div class="rail-note">${icon("shield")}<p>Small circle. Big memories.<br>Your moments belong with your people.</p></div><div class="rail-footer">LOOP FOR DESKTOP <span style="float:right">✧</span><p style="margin-top:7px">Local demo · Made for a little more together.</p></div></aside>`;
}
function wall() {
  return `<div class="wall-intro">${icon("smile")}<div><h3>A little chaos. All in good fun.</h3><p>Anonymous, always. Keep it funny, not cruel.</p></div></div><div class="wall-grid">${(sort === "popular" ? [...state.wall].sort((a, b) => b.laughs - a.laughs) : state.wall).map((p) => `<article class="wall-post">${p.image ? `<img src="${esc(p.image)}" alt="Anonymous circle moment"><p style="padding:14px">${esc(p.text)}</p>` : `<div class="wall-text">${esc(p.text).replace(/\n/g, "<br>")}</div>`}<footer><button data-laugh="${p.id}" aria-pressed="${p.liked}">☺ ${p.laughs} laughs</button><small>Anonymous</small></footer></article>`).join("")}</div><p class="end-note">Only your circle gets the joke.</p>`;
}
function chatName(id) {
  return id === "circle" ? state.circle : person(id).name;
}
function chats() {
  const list = Object.keys(state.chats).filter((id) =>
    chatName(id).toLowerCase().includes(chatQuery.toLowerCase()),
  );
  return `${heading("Messages", "Good conversations start here.", "new-chat", "New message")}<div class="chat-layout"><aside class="chat-list" aria-label="Conversations"><form class="search" id="chat-search">${icon("search")}<input name="q" placeholder="Find a conversation" aria-label="Find a conversation" value="${esc(chatQuery)}"></form>${list.map((id) => `<button class="chat-item ${id === selectedChat ? "active" : ""}" data-chat="${id}" ${id === selectedChat ? 'aria-current="true"' : ""}>${id === "circle" ? `<span class="avatar">${icon("people")}</span>` : avatar(id)}<span class="grow"><strong>${esc(chatName(id))}</strong><small>${esc(state.chats[id].at(-1)?.text || "Start a conversation")}</small></span></button>`).join("") || '<p class="muted">No conversations found.</p>'}</aside><section class="chat-room" aria-label="Chat with ${esc(chatName(selectedChat))}"><header class="chat-header row">${selectedChat === "circle" ? `<span class="avatar">${icon("people")}</span>` : avatar(selectedChat, "online")}<div class="grow"><h3>${esc(chatName(selectedChat))}</h3><small>${selectedChat === "circle" ? "6 people · " : ""}Local demo conversation</small></div>${icon("lock")}</header><div class="messages" aria-live="polite"><p class="chat-date">A little conversation, just for you</p>${state.chats[selectedChat].map((m) => `<div class="message ${m.mine ? "mine" : ""}">${!m.mine ? `<small style="margin-bottom:5px">${esc(m.name || chatName(selectedChat))}</small>` : ""}<div class="bubble">${esc(m.text)}</div><small>${esc(m.time)} ${m.mine ? "· Saved locally" : ""}</small></div>`).join("")}</div><form class="message-form" id="message-form"><input name="message" aria-label="Message" placeholder="Write a message…" maxlength="2000" autocomplete="off" required><button class="primary" aria-label="Send message">${icon("send")}</button></form></section></div>`;
}
function setting(key, title, description, i) {
  return `<div class="setting-row">${icon(i)}<div class="grow"><h3>${title}</h3><small>${description}</small></div><button class="switch" role="switch" aria-label="${title}" aria-checked="${state[key]}" data-toggle="${key}"></button></div>`;
}
function settings() {
  return `${heading("Make yourself at home.", "Your Loop, just how you like it.")}<div class="settings-grid"><section class="section-card"><h2>Appearance & theme</h2><p>A different mood. The same people.</p><div class="themes">${["aurora", "onyx", "daylight"].map((t) => `<button class="theme-choice ${state.theme === t ? "active" : ""}" data-theme-choice="${t}" aria-pressed="${state.theme === t}"><div class="theme-preview ${t}"></div><span>${t[0].toUpperCase() + t.slice(1)}</span>${state.theme === t ? '<span style="float:right;color:var(--accent)">✓</span>' : ""}</button>`).join("")}</div></section><section class="section-card"><h2>Privacy & your circle</h2><p>You choose what you’re comfortable with.</p>${setting("consent", "Let friends post me on the Troll Wall", "A local preference for this demo.", "smile")}</section><section class="section-card"><h2>Notifications & sounds</h2><p>Personalize your local preview.</p>${setting("notifications", "In-app activity", "Show the recent activity panel.", "bell")}${setting("sounds", "Message sounds", "Play a gentle tone when you send a message.", "chat")}</section><section class="section-card"><h2>Your browser data</h2><p>Posts, messages, and preferences stay in this browser. This preview is not connected to an account or server.</p><div class="row">${icon("log")}<div class="grow"><h3>Local demo</h3><small>No sign-in or backend connection</small></div><button class="secondary" data-action="reset">Reset demo</button></div></section></div>`;
}
function profile() {
  const myPosts = state.posts.filter((p) => p.person === "me");
  return `${heading("Your corner of the loop.", "A little about the person behind the moments.")}<div class="layout"><section><div class="profile-cover"></div><div class="profile-body"><div class="row">${avatar("me")}<button class="primary" data-action="edit-profile">${icon("edit")}Edit profile</button></div><h2>${esc(state.profile.name)}</h2><small>@${esc(state.profile.name.toLowerCase().replace(/\s/g, ""))}</small><p class="profile-bio">${esc(state.profile.bio)}</p><p class="row muted" style="font-size:12px;margin-top:15px">${icon("location")}${esc(state.profile.location)}</p><div class="profile-stats"><div><strong>${myPosts.length}</strong><small>Moments shared</small></div><div><strong>6</strong><small>People in your circle</small></div><div><strong>${state.posts.filter((p) => p.saved).length}</strong><small>Saved moments</small></div></div></div><h2 style="margin:27px 0 17px">Your moments</h2>${myPosts.length ? myPosts.map(post).join("") : `<div class="section-card empty">${icon("image")}<h3>Your story is just getting started.</h3><p style="margin:8px 0 20px">Share a little moment with your people.</p><button class="primary" data-action="compose">Share a moment</button></div>`}${
    state.posts.some((p) => p.saved)
      ? `<h2 style="margin:27px 0 17px">Saved for later</h2>${state.posts
          .filter((p) => p.saved)
          .map(post)
          .join("")}`
      : ""
  }</section>${rail()}</div>`;
}
function searchPage() {
  const q = query.trim().toLowerCase();
  const foundPeople = people.filter((p) => p.name.toLowerCase().includes(q));
  const foundPosts = state.posts.filter((p) =>
    (p.text + " " + person(p.person).name).toLowerCase().includes(q),
  );
  return `${heading("A little searching.", "Find your people and the moments they’ve shared.")}<section class="results">${q ? `<h2>People</h2>${foundPeople.map((p) => `<button class="search-result" data-chat="${p.id}">${avatar(p.id)}<span class="grow">${p.name}</span>${icon("chat")}</button>`).join("") || '<p class="muted" style="padding:20px 0">No people found.</p>'}<h2 style="margin:30px 0 20px">Moments</h2>${foundPosts.map(post).join("") || '<p class="muted">No moments match that search. Try another word.</p>'}` : '<div class="empty">Search for a name or a word from a post.</div>'}</section>`;
}
function showModal(title, body) {
  modal.innerHTML = `<header class="modal-heading"><h2 id="modal-title">${title}</h2>${buttonIcon("close", "Close dialog", "close")}</header>${body}`;
  if (!modal.open) modal.showModal();
}
function composer(anonymous = false, story = false) {
  showModal(
    story
      ? "Add a little moment"
      : anonymous
        ? "Let the circle laugh"
        : "Share with your people",
    `<form id="post-form" data-anonymous="${anonymous}" data-story="${story}"><p class="muted" style="font-size:12px">${story ? "A moment for your circle. Stored in this browser for 24 hours." : anonymous ? "No names attached in this demo. Keep it kind." : "Something big, something small. It all belongs here."}</p><label class="form-field">${story ? "Caption" : "Your moment"}<textarea name="text" maxlength="2000" placeholder="${anonymous ? "The group chat needs to see this…" : "What’s on your mind?"}"></textarea></label><label class="upload">${icon("image")}<input type="file" name="photo" accept="image/jpeg,image/png,image/webp" aria-label="Add a photo"></label><div id="photo-preview"></div><p class="tiny muted" style="margin-top:10px">Photos up to 3 MB · Saved only in this browser</p><div class="form-actions"><button type="button" class="secondary" data-action="close">Cancel</button><button class="primary" type="submit">${story ? "Add story" : anonymous ? "Post anonymously" : "Share moment"} ${icon("arrow")}</button></div></form>`,
  );
}
function comments(id) {
  const p = state.posts.find((p) => p.id === id);
  showModal(
    "A little conversation",
    `<div>${p.comments.map((c) => `<div class="comment"><strong>${esc(c.name)}</strong><p>${esc(c.text)}</p></div>`).join("") || '<p class="muted">Be the first to say something.</p>'}</div><form id="comment-form" data-id="${id}"><label class="form-field">Your reply<input name="comment" placeholder="Leave a little love…" maxlength="500" required></label><div class="form-actions"><button class="primary">Add comment</button></div></form>`,
  );
}
function openChat(id) {
  selectedChat = id;
  state.chats[id] ??= [];
  persist();
  page = "chats";
  query = "";
  modal.close();
  render();
}
function scrollMessages() {
  const el = document.querySelector(".messages");
  if (el) el.scrollTop = el.scrollHeight;
}
function playTone() {
  if (!state.sounds) return;
  try {
    const ctx = new AudioContext();
    const oscillator = ctx.createOscillator();
    const gain = ctx.createGain();
    oscillator.connect(gain);
    gain.connect(ctx.destination);
    oscillator.frequency.value = 620;
    gain.gain.setValueAtTime(0.04, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.15);
    oscillator.start();
    oscillator.stop(ctx.currentTime + 0.16);
    oscillator.onended = () => ctx.close();
  } catch {
    /* Audio is optional when the browser disables it. */
  }
}
async function imageData(file) {
  if (!file) return "";
  if (!["image/jpeg", "image/png", "image/webp"].includes(file.type))
    throw Error("Choose a JPG, PNG, or WebP photo.");
  if (file.size > 3 * 1024 * 1024)
    throw Error("Choose a photo smaller than 3 MB.");
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 1200 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  return canvas.toDataURL("image/jpeg", 0.82);
}
document.addEventListener("click", (event) => {
  const b = event.target.closest("button,a");
  if (!b) return;
  if (b.matches('a[href="#home"]')) {
    event.preventDefault();
    page = "home";
    query = "";
    render();
    return;
  }
  if (b.dataset.page) {
    page = b.dataset.page;
    query = "";
    render();
    window.scrollTo(0, 0);
  }
  if (b.dataset.tab) {
    tab = b.dataset.tab;
    render();
  }
  if (b.dataset.chat) openChat(b.dataset.chat);
  if (b.dataset.themeChoice) {
    state.theme = b.dataset.themeChoice;
    persist();
    render();
  }
  if (b.dataset.toggle) {
    const k = b.dataset.toggle;
    state[k] = !state[k];
    persist();
    render();
  }
  if (b.dataset.like) {
    const p = state.posts.find((p) => p.id === b.dataset.like);
    p.liked = !p.liked;
    p.likes += p.liked ? 1 : -1;
    persist();
    render();
  }
  if (b.dataset.save) {
    const p = state.posts.find((p) => p.id === b.dataset.save);
    p.saved = !p.saved;
    persist();
    render();
    toast(p.saved ? "Saved to your profile." : "Removed from saved moments.");
  }
  if (b.dataset.laugh) {
    const p = state.wall.find((p) => p.id === b.dataset.laugh);
    p.liked = !p.liked;
    p.laughs += p.liked ? 1 : -1;
    persist();
    render();
  }
  if (b.dataset.comments) comments(b.dataset.comments);
  if (b.dataset.options) {
    const p = state.posts.find((p) => p.id === b.dataset.options);
    showModal(
      "This moment",
      `<p class="muted" style="margin-bottom:20px">Shared by ${esc(person(p.person).name)} in your local demo circle.</p><button class="secondary wide" data-save="${p.id}" data-action="close">${icon("bookmark")}${p.saved ? "Remove from saved" : "Save for later"}</button>${p.person === "me" ? `<button class="secondary wide" style="margin-top:12px" data-delete-post="${p.id}">Delete my post</button>` : ""}`,
    );
  }
  if (b.dataset.deletePost) {
    state.posts = state.posts.filter((p) => p.id !== b.dataset.deletePost);
    persist();
    modal.close();
    render();
    toast("Your post was deleted.");
  }
  if (b.dataset.story) {
    const id = b.dataset.story;
    if (id === "mine") {
      const story = state.stories
        .filter((s) => Date.now() - s.created < 86400000)
        .at(-1);
      if (!story) {
        toast("Your story has expired. Add a new moment.");
        return;
      }
      showModal(
        "Your latest moment",
        `${story.image ? `<img class="story-image" src="${esc(story.image)}" alt="Your story">` : ""}<p style="margin-top:15px">${esc(story.text)}</p>`,
      );
    } else {
      const image =
        id === "alex" || id === "sofia"
          ? "coast"
          : id === "radu" || id === "teo"
            ? "mountain"
            : "city";
      showModal(
        `${person(id).name}’s moment`,
        `<img class="story-image" src="assets/${image}.jpg" alt="A scenic moment shared by ${person(id).name}"><p class="muted" style="margin-top:14px">A little out of the ordinary. ✨</p><p class="tiny muted" style="margin-top:6px">Demo story</p>`,
      );
    }
  }
  const action = b.dataset.action;
  if (action === "close") modal.close();
  if (action === "compose") composer();
  if (action === "anonymous") composer(true);
  if (action === "add-story") composer(false, true);
  if (action === "circle")
    showModal(
      "Your inner circle",
      `<p class="muted" style="font-size:13px;margin-bottom:18px">Six people. A shared little world.</p><form id="circle-form"><label class="form-field">Circle name<input name="name" value="${esc(state.circle)}" maxlength="30" required></label><button class="secondary wide">Save circle name</button></form><div style="margin-top:18px">${people.map((p) => `<button class="friend" data-chat="${p.id}">${avatar(p.id, p.online ? "online" : "")}<span class="grow">${p.name}</span>${icon("chat")}</button>`).join("")}</div><p class="tiny muted" style="margin-top:16px">These are sample members. Real invitations will be available when accounts are connected.</p>`,
    );
  if (action === "new-chat")
    showModal(
      "Start a conversation",
      `<p class="muted" style="margin-bottom:12px">Pick someone from your circle.</p>${people.map((p) => `<button class="friend" data-chat="${p.id}">${avatar(p.id)}<span class="grow">${p.name}</span>${icon("arrow")}</button>`).join("")}`,
    );
  if (action === "edit-profile")
    showModal(
      "A little about you",
      `<form id="profile-form"><label class="form-field">Display name<input name="name" value="${esc(state.profile.name)}" maxlength="30" required></label><label class="form-field">Bio<textarea name="bio" maxlength="200">${esc(state.profile.bio)}</textarea></label><label class="form-field">Location<input name="location" value="${esc(state.profile.location)}" maxlength="80"></label><div class="form-actions"><button type="button" class="secondary" data-action="close">Cancel</button><button class="primary">Save changes</button></div></form>`,
    );
  if (action === "notifications")
    showModal(
      "In the loop",
      state.notifications
        ? `<p class="tiny muted" style="margin-bottom:15px">SAMPLE ACTIVITY</p><div class="friend">${avatar("mia")}<span><strong>Mia</strong> left a little love on a moment.<br><small>20 minutes ago</small></span></div><div class="friend">${avatar("alex")}<span><strong>Alex</strong> shared a new photo.<br><small>2 hours ago</small></span></div><div class="friend">${avatar("radu")}<span><strong>Radu</strong> added a story.<br><small>3 hours ago</small></span></div>`
        : '<p class="muted">Activity is paused. You can turn it back on in Settings.</p>',
    );
  if (action === "reset")
    showModal(
      "Start fresh?",
      `<p class="muted">This removes the posts, messages, stories, and preferences you added to this browser’s demo.</p><div class="form-actions"><button class="secondary" data-action="close">Keep my changes</button><button class="primary" data-action="confirm-reset">Reset demo</button></div>`,
    );
  if (action === "confirm-reset") {
    state = initial();
    selectedChat = "circle";
    persist();
    modal.close();
    render();
    toast("A fresh start. Demo data restored.");
  }
});
document.addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.target;
  const data = new FormData(form);
  if (form.id === "search-form") {
    query = String(data.get("q")).trim();
    page = "search";
    render();
  }
  if (form.id === "chat-search") {
    chatQuery = String(data.get("q")).trim();
    render();
  }
  if (form.id === "message-form") {
    const text = String(data.get("message")).trim();
    if (!text) return;
    state.chats[selectedChat].push({
      text,
      mine: true,
      time: new Date().toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit",
      }),
    });
    persist();
    playTone();
    render();
    document.querySelector('[name="message"]').focus();
  }
  if (form.id === "comment-form") {
    const text = String(data.get("comment")).trim();
    if (!text) return;
    state.posts
      .find((p) => p.id === form.dataset.id)
      .comments.push({ name: state.profile.name, text });
    persist();
    render();
    comments(form.dataset.id);
  }
  if (form.id === "profile-form") {
    const name = String(data.get("name")).trim();
    if (!name) {
      toast("Add a display name first.");
      return;
    }
    state.profile = {
      name,
      bio: String(data.get("bio")).trim(),
      location: String(data.get("location")).trim(),
    };
    persist();
    modal.close();
    render();
    toast("Looking good. Profile updated.");
  }
  if (form.id === "circle-form") {
    const name = String(data.get("name")).trim();
    if (!name) {
      toast("Give your circle a name.");
      return;
    }
    state.circle = name;
    persist();
    modal.close();
    render();
    toast("Circle name updated.");
  }
  if (form.id === "post-form") {
    const text = String(data.get("text")).trim();
    const file = data.get("photo");
    const submit = form.querySelector('[type="submit"]');
    if (!text && !file?.size) {
      toast("Add a thought or a photo first.");
      return;
    }
    submit.disabled = true;
    try {
      const image = file?.size ? await imageData(file) : "";
      const id = crypto.randomUUID();
      if (form.dataset.story === "true") {
        state.stories = state.stories.filter(
          (s) => Date.now() - s.created < 86400000,
        );
        state.stories.push({ id, text, image, created: Date.now() });
      } else if (form.dataset.anonymous === "true") {
        state.wall.unshift({ id, text, image, laughs: 0, liked: false });
        page = "home";
        tab = "wall";
      } else {
        state.posts.unshift({
          id,
          person: "me",
          text,
          image,
          time: "Just now",
          likes: 0,
          liked: false,
          saved: false,
          comments: [],
        });
      }
      persist();
      modal.close();
      render();
      toast("Your moment is saved in this browser.");
    } catch (error) {
      toast(error.message);
      submit.disabled = false;
    }
  }
});
document.addEventListener("change", async (event) => {
  if (event.target.matches(".sort")) {
    sort = event.target.value;
    render();
  }
  if (event.target.matches('[name="photo"]')) {
    const target = event.target;
    const preview = document.querySelector("#photo-preview");
    preview.replaceChildren();
    try {
      const src = await imageData(target.files[0]);
      if (src && preview.isConnected) {
        const img = document.createElement("img");
        img.src = src;
        img.alt = "Selected photo preview";
        img.className = "preview-image";
        preview.replaceChildren(img);
      }
    } catch (error) {
      target.value = "";
      toast(error.message);
    }
  }
});
document.addEventListener("keydown", (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    if (!modal.open) document.querySelector("#search-form input").focus();
  }
});
modal.addEventListener("click", (event) => {
  if (event.target === modal) {
    const r = modal.getBoundingClientRect();
    if (
      event.clientX < r.left ||
      event.clientX > r.right ||
      event.clientY < r.top ||
      event.clientY > r.bottom
    )
      modal.close();
  }
});
render();
