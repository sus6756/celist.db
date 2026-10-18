/* ================================================================
   celist.db Windows — renderer.js
   Single-page app: welcome → table grid → designer → SQL editor.
   Uses sql.js (WASM) for the SQLite engine; file I/O via Electron IPC.
   ================================================================ */

// ---- sql.js loader (via window.sqlInitFactory set by load script) ----
let SQL = null;          // set after initSqlJs resolves
let db = null;           // current sql.js Database
let dbPath = null;       // path of the currently-open .db file

// ---- App state ---------------------------------------------------
const S = {
  view: 'welcome',      // 'welcome' | 'grid' | 'designer' | 'query'
  ribbonTab: 'Home',
  sidebarSelection: null, // { type:'table'|'view', name } or { type:'action'|'newTable'|'query' }
  objects: [],           // [{ name, kind }] from sqlite_master
  rowCounts: {},         // table name -> row count, for the sidebar
  tableSchema: null,     // { columns: [{ name, type, pk, notnull, dflt }], pkCols: string[], fks: [], isView: bool }
  isView: false,         // true when the open sidebar object is a view (read-only)
  rows: [],
  totalRows: 0,
  page: 0,
  limit: 500,
  sortCol: null,
  sortAsc: true,
  searchText: '',
  selectedRowID: null,   // rowid
  editingCell: null,     // { rowid, col }
  editingText: '',
  designer: {
    tableName: '',
    columns: [],
  },
  query: {
    sql: '',
    result: null,        // { columns, rows, rowCount, isDataQuery }
    error: null,
    history: [],
  },
  message: '',
};

// ---- Bootstrap ---------------------------------------------------
(async function boot() {
  const initSqlJs = window.initSqlJs;
  SQL = await initSqlJs({ locateFile: f => `../node_modules/sql.js/dist/${f}` });
  loadQueryHistory();
  renderWelcome();
  renderNavPane();
  renderRibbon();
  setupGlobalListeners();
})();

/// Query history is persisted in localStorage so it survives relaunches.
function loadQueryHistory() {
  try {
    const raw = localStorage.getItem('celistdb.queryHistory');
    if (raw) S.query.history = JSON.parse(raw) || [];
  } catch { S.query.history = []; }
}

function persistQueryHistory() {
  try { localStorage.setItem('celistdb.queryHistory', JSON.stringify(S.query.history)); } catch {}
}

// ================================================================
//  Persistence helpers
// ================================================================

function loadDB(path) {
  if (!path) return Promise.resolve();
  return celistdb.readFile(path).then(data => {
    let next;
    try {
      // Parse into a fresh handle first so a bad file never clobbers the
      // currently-open database.
      next = data ? new SQL.Database(new Uint8Array(data.bytes)) : new SQL.Database();
    } catch (e) {
      showAlert('Could not open database', 'This file could not be read as a SQLite database.\n\n' + (e.message || e));
      return;
    }
    if (db) { try { db.close(); } catch {} }
    db = next;
    dbPath = path;
    // Do NOT write back here — opening must be read-only until the user edits.
    refreshObjects();
    updateDBName();
    renderNavPane();
  }).catch(e => {
    showAlert('Could not open database', String(e.message || e));
  });
}

function newDB(path) {
  if (!path) return Promise.resolve();
  dbPath = path;
  db = new SQL.Database();
  return saveToDisk().then(() => {
    refreshObjects();
    updateDBName();
    renderNavPane();
  });
}

function saveToDisk() {
  if (!db || !dbPath) return Promise.resolve();
  const bytes = db.export();
  return celistdb.writeFile(dbPath, Array.from(bytes));
}

function updateDBName() {
  const el = document.getElementById('db-name');
  if (el) el.textContent = dbPath ? dbPath.split(/[\\/]/).pop() : '';
}

function refreshObjects() {
  S.objects = [];
  S.rowCounts = {};
  if (!db) return;
  try {
    const res = db.exec("SELECT name,type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY type DESC, name COLLATE NOCASE");
    if (res.length) S.objects = res[0].values.map(r => ({ name: String(r[0]), kind: String(r[1]) }));
    for (const o of S.objects) {
      if (o.kind !== 'table') continue;
      try {
        const c = db.exec(`SELECT COUNT(*) FROM "${o.name.replace(/"/g, '""')}"`);
        S.rowCounts[o.name] = c.length ? Number(c[0].values[0][0]) : 0;
      } catch { S.rowCounts[o.name] = 0; }
    }
  } catch {}
  renderNavPane();
}

function refreshSchema(tableName) {
  S.tableSchema = null;
  S.isView = false;
  if (!db || !tableName) return;
  try {
    const q = String(tableName).replace(/'/g, "''");
    const info = db.exec(`PRAGMA table_info('${q}')`);
    const fkInfo = db.exec(`PRAGMA foreign_key_list('${q}')`);
    const kindRes = db.exec(`SELECT type FROM sqlite_master WHERE name = '${q}' LIMIT 1`);
    const isView = kindRes.length > 0 && String(kindRes[0].values[0][0]) === 'view';
    if (info.length === 0) return;

    // `table_info` already reports primary-key membership in column 5 (the
    // order within a composite key). Use that instead of a non-existent pragma.
    const columns = info[0].values.map(r => ({
      cid: r[0],
      name: String(r[1]),
      type: r[2] ? String(r[2]) : '',
      notnull: r[3] === 1,
      dflt: r[4],
      pkOrder: Number(r[5]) || 0,
    }));
    columns.forEach(c => { c.pk = c.pkOrder > 0; });
    const pkCols = columns.filter(c => c.pkOrder > 0)
      .sort((a, b) => a.pkOrder - b.pkOrder)
      .map(c => c.name);

    // foreign_key_list columns: id, seq, table, from, to, on_update, on_delete, match
    const fks = fkInfo.length ? fkInfo[0].values.map(r => ({
      id: r[0], from: String(r[3]), toTable: String(r[2]), toCol: String(r[4]),
    })) : [];

    S.tableSchema = { columns, pkCols, fks, isView };
    S.isView = isView;
  } catch (e) { S.message = e.message; }
}

// ================================================================
//  Navigation Pane
// ================================================================

function renderNavPane() {
  const pane = document.getElementById('nav-pane');
  const tables = S.objects.filter(o => o.kind === 'table');
  const views  = S.objects.filter(o => o.kind === 'view');

  let html = `
    <div class="np-header">
      <span class="np-header-icon">🗄️</span>
      <span class="np-header-text">All Access Objects</span>
      <button class="np-header-menu" id="np-menu-btn" title="Refresh">⟳</button>
    </div>
    <div class="np-scroll">
      <button class="np-action" data-sel='{"type":"newTable"}'>
        <span class="np-action-icon">📎</span>
        <div class="np-action-text">
          <span class="np-action-title">New Table</span>
          <span class="np-action-subtitle">Design a table</span>
        </div>
      </button>
      <button class="np-action" data-sel='{"type":"query"}'>
        <span class="np-action-icon">⌨️</span>
        <div class="np-action-text">
          <span class="np-action-title">SQL Query</span>
          <span class="np-action-subtitle">Raw SQL editor</span>
        </div>
      </button>
      <div class="np-sep"></div>
  `;
  if (tables.length) {
    html += `<button class="np-group-header"><span class="np-chevron">▾</span><span class="np-group-title">Tables</span><span class="np-group-count">(${tables.length})</span></button>`;
    tables.forEach(t => {
      const sel = S.sidebarSelection && S.sidebarSelection.type === 'table' && S.sidebarSelection.name === t.name;
      const count = S.rowCounts[t.name];
      html += `<button class="np-item${sel?' selected':''}" data-sel='${JSON.stringify({type:'table',name:t.name})}'><span class="np-item-icon">📊</span><span class="np-item-name">${esc(t.name)}</span>${count!==undefined?`<span class="np-item-count">${count}</span>`:''}</button>`;
    });
  }
  if (views.length) {
    html += `<button class="np-group-header"><span class="np-chevron">▾</span><span class="np-group-title">Views</span><span class="np-group-count">(${views.length})</span></button>`;
    views.forEach(v => {
      const sel = S.sidebarSelection && S.sidebarSelection.type === 'view' && S.sidebarSelection.name === v.name;
      html += `<button class="np-item${sel?' selected':''}" data-sel='${JSON.stringify({type:'view',name:v.name})}'><span class="np-item-icon">👁️</span><span class="np-item-name">${esc(v.name)}</span></button>`;
    });
  }
  if (!tables.length && !views.length) {
    html += `<div class="np-empty"><div>🗄️</div>This database is empty.<br>Create a table to get started.</div>`;
  }
  html += `</div>`;
  pane.innerHTML = html;

  // Bind clicks
  pane.querySelectorAll('[data-sel]').forEach(btn => {
    btn.addEventListener('click', () => {
      const sel = JSON.parse(btn.dataset.sel);
      selectSidebar(sel);
    });
  });
  pane.querySelector('#np-menu-btn')?.addEventListener('click', () => {
    if (db) { refreshObjects(); toast('Sidebar refreshed', 'info'); }
  });
}

function selectSidebar(sel) {
  S.sidebarSelection = sel;
  if (sel.type === 'newTable') {
    showDesigner();
  } else if (sel.type === 'query') {
    showQuery();
  } else if (sel.type === 'table' || sel.type === 'view') {
    showTable(sel.name);
  }
  renderNavPane();
  renderRibbon();
}

// ================================================================
//  Ribbon
// ================================================================

const RIBBON_TABS = ['Home','Create','External Data','Database Tools','File'];

function renderRibbon() {
  const tabStrip = document.getElementById('tab-strip');
  tabStrip.innerHTML = RIBBON_TABS.map(t =>
    `<button class="ribbon-tab${S.ribbonTab===t?' active':''}" data-tab="${t}">${t}</button>`
  ).join('');
  tabStrip.querySelectorAll('.ribbon-tab').forEach(b => {
    b.addEventListener('click', () => { S.ribbonTab = b.dataset.tab; renderRibbon(); });
  });
  const area = document.getElementById('group-area');
  switch (S.ribbonTab) {
    case 'Home':   renderHomeTab(area); break;
    case 'Create': renderCreateTab(area); break;
    case 'External Data': renderExternalTab(area); break;
    case 'Database Tools': renderDBToolsTab(area); break;
    case 'File':   renderFileTab(area); break;
  }
}

function rbtn(icon, label, enabled, onClick) {
  return `<button class="rbtn${enabled?'':' disabled'}" ${enabled?'':'disabled'} title="${esc(label)}">${icon?'<span class="rbtn-icon">'+icon+'</span>':''}<span>${label}</span></button>`;
}

function renderHomeTab(area) {
  const hasRow = S.view === 'grid' && S.selectedRowID !== null;
  const hasTable = S.view === 'grid';
  const editable = hasTable && !S.isView;

  area.innerHTML = `
    <div class="ribbon-group">
      <div class="ribbon-group-buttons">
        <button class="rbtn${editable?'':' disabled'}" id="rb-new-rec" ${editable?'':'disabled'} title="${S.isView?'Views are read-only':'Add a new record'}"><span class="rbtn-icon">➕</span><span>New</span></button>
        <button class="rbtn${editable&&hasRow?'':' disabled'}" id="rb-dup" ${editable&&hasRow?'':'disabled'} title="Duplicate the selected record"><span class="rbtn-icon">📋</span><span>Duplicate</span></button>
        <button class="rbtn${editable&&hasRow?'':' disabled'}" id="rb-del" ${editable&&hasRow?'':'disabled'} title="Delete the selected record"><span class="rbtn-icon">🗑️</span><span>Delete</span></button>
        <button class="rbtn${hasTable?'':' disabled'}" id="rb-refresh" ${hasTable?'':'disabled'} title="Reload the datasheet"><span class="rbtn-icon">🔄</span><span>Refresh</span></button>
      </div>
      <div class="ribbon-group-label">Records</div>
    </div>
    <div class="ribbon-sep"></div>
    <div class="ribbon-group">
      <div class="ribbon-group-buttons">
        <button class="rbtn${hasTable?'':' disabled'}" id="rb-asc" ${hasTable?'':'disabled'} title="Sort ascending"><span class="rbtn-icon">⬆</span><span>Ascending</span></button>
        <button class="rbtn${hasTable?'':' disabled'}" id="rb-desc" ${hasTable?'':'disabled'} title="Sort descending"><span class="rbtn-icon">⬇</span><span>Descending</span></button>
        <button class="rbtn" id="rb-clear" title="Clear filter"><span class="rbtn-icon">🚫</span><span>Clear</span></button>
      </div>
      <div class="ribbon-group-label">Sort &amp; Filter</div>
    </div>
    <div class="ribbon-sep"></div>
    <div class="ribbon-group">
      <div class="ribbon-group-buttons" style="flex-direction:column">
        <input type="text" class="rf-input" id="rb-search" placeholder="Find in datasheet…" value="${esc(S.searchText)}" ${hasTable?'':'disabled'}>
        <span style="font-size:10px;color:#888;margin-top:4px">${hasTable?'Filter all columns live':'Open a table to search'}</span>
      </div>
      <div class="ribbon-group-label">Search</div>
    </div>
  `;
  if (hasRow) {
    document.getElementById('rb-dup')?.addEventListener('click', duplicateRow);
    document.getElementById('rb-del')?.addEventListener('click', deleteRow);
  }
  if (editable) {
    document.getElementById('rb-new-rec')?.addEventListener('click', addRow);
  }
  if (hasTable) {
    document.getElementById('rb-refresh')?.addEventListener('click', reloadCurrentTable);
    document.getElementById('rb-search')?.addEventListener('input', e => { S.searchText = e.target.value; debouncedReload(); });
  }
  document.getElementById('rb-asc')?.addEventListener('click', () => sortByColumn(true));
  document.getElementById('rb-desc')?.addEventListener('click', () => sortByColumn(false));
  document.getElementById('rb-clear')?.addEventListener('click', clearSortFilter);
}

/// Sort the current column, defaulting to the first column when the user
/// hasn't clicked one yet (the ribbon buttons used to stay disabled).
function sortByColumn(ascending) {
  if (!S.sortCol) S.sortCol = S.tableSchema?.columns?.[0]?.name || null;
  if (!S.sortCol) return;
  S.sortAsc = ascending;
  reloadCurrentTable();
}

function renderCreateTab(area) {
  area.innerHTML = `
    <div class="ribbon-group"><div class="ribbon-group-buttons">
      <button class="rbtn" id="rb-new-table" title="Design a new table"><span class="rbtn-icon">📊</span><span>Table</span></button>
      <button class="rbtn" id="rb-sample" title="Create sample shop database"><span class="rbtn-icon">✨</span><span>Sample DB</span></button>
    </div><div class="ribbon-group-label">Tables</div></div>
    <div class="ribbon-sep"></div>
    <div class="ribbon-group"><div class="ribbon-group-buttons">
      <button class="rbtn" id="rb-sql-q" title="Open the raw SQL editor"><span class="rbtn-icon">⌨️</span><span>SQL Query</span></button>
    </div><div class="ribbon-group-label">Queries</div></div>
  `;
  document.getElementById('rb-new-table')?.addEventListener('click', () => selectSidebar({ type: 'newTable' }));
  document.getElementById('rb-sample')?.addEventListener('click', createSampleDB);
  document.getElementById('rb-sql-q')?.addEventListener('click', () => selectSidebar({ type: 'query' }));
}

function renderExternalTab(area) {
  const hasTable = S.view === 'grid' && !!S.sidebarSelection;
  const hasResult = S.view === 'query' && !!S.query.result && S.query.result.isDataQuery;
  area.innerHTML = `
    <div class="ribbon-group"><div class="ribbon-group-buttons">
      <button class="rbtn${db?'':' disabled'}" id="rb-import" ${db?'':'disabled'} title="Import a CSV file as a new table"><span class="rbtn-icon">📥</span><span>CSV Import</span></button>
      <button class="rbtn${db?'':' disabled'}" id="rb-import-json" ${db?'':'disabled'} title="Import a JSON file (array of objects) as a new table"><span class="rbtn-icon">📥</span><span>JSON Import</span></button>
    </div><div class="ribbon-group-label">Import &amp; Link</div></div>
    <div class="ribbon-sep"></div>
    <div class="ribbon-group"><div class="ribbon-group-buttons">
      <button class="rbtn${(hasTable||hasResult)?'':' disabled'}" id="rb-export" ${(hasTable||hasResult)?'':'disabled'} title="Export the current table or query results to CSV"><span class="rbtn-icon">📤</span><span>CSV Export</span></button>
    </div><div class="ribbon-group-label">Export</div></div>
  `;
  document.getElementById('rb-import')?.addEventListener('click', importCSV);
  document.getElementById('rb-import-json')?.addEventListener('click', importJSON);
  document.getElementById('rb-export')?.addEventListener('click', exportCSV);
}

function renderDBToolsTab(area) {
  area.innerHTML = `
    <div class="ribbon-group"><div class="ribbon-group-buttons">
      <button class="rbtn${db?'':' disabled'}" id="rb-relationships" ${db?'':'disabled'} title="Show the foreign-key relationships between tables"><span class="rbtn-icon">🔗</span><span>Relationships</span></button>
      <button class="rbtn${dbPath?'':' disabled'}" id="rb-backup" ${dbPath?'':'disabled'} title="Save a backup copy of this database"><span class="rbtn-icon">💾</span><span>Backup DB</span></button>
    </div><div class="ribbon-group-label">Tools</div></div>
  `;
  document.getElementById('rb-relationships')?.addEventListener('click', showRelationships);
  document.getElementById('rb-backup')?.addEventListener('click', backupDatabase);
}

function renderFileTab(area) {
  area.innerHTML = `
    <div class="ribbon-group"><div class="ribbon-group-buttons">
      <button class="rbtn" id="rb-open" title="Open an existing database"><span class="rbtn-icon">📂</span><span>Open…</span></button>
      <button class="rbtn" id="rb-new" title="Create a new database"><span class="rbtn-icon">➕</span><span>New…</span></button>
    </div><div class="ribbon-group-label">Database</div></div>
    <div class="ribbon-sep"></div>
    <div class="ribbon-group"><div class="ribbon-group-buttons">
      <button class="rbtn" id="rb-about" title="About celist.db"><span class="rbtn-icon">ℹ️</span><span>About</span></button>
      <button class="rbtn" id="rb-close-db" title="Close the current database"><span class="rbtn-icon">❌</span><span>Close DB</span></button>
    </div><div class="ribbon-group-label">Support</div></div>
  `;
  document.getElementById('rb-open')?.addEventListener('click', openDatabase);
  document.getElementById('rb-new')?.addEventListener('click', createNewDatabase);
  document.getElementById('rb-about')?.addEventListener('click', () => showAlert('About celist.db', `celist.db — the database app for the rest of us.\nVersion 1.0.0 (Windows edition)\n\nBuilt with Electron + SQLite (sql.js).\n\nA simplified database manager combining elements of MS Access, MySQL Workbench, and phpMyAdmin.`));
  document.getElementById('rb-close-db')?.addEventListener('click', closeDatabase);
}

// ================================================================
//  Views: Welcome
// ================================================================

function renderWelcome() {
  S.view = 'welcome';
  S.sidebarSelection = null;
  document.getElementById('detail').innerHTML = `
    <div class="welcome">
      <div class="welcome-inner">
        <h2>Welcome to celist.db</h2>
        <p>The database app for the rest of us.<br>A simplified database manager for Windows — inspired by Microsoft Access.</p>
        <div class="welcome-actions">
          <button class="welcome-card" id="w-open"><div class="welcome-card-icon">📂</div><div class="welcome-card-title">Open Database</div><div class="welcome-card-sub">Open an existing .db file</div></button>
          <button class="welcome-card" id="w-new"><div class="welcome-card-icon">📝</div><div class="welcome-card-title">Blank Database</div><div class="welcome-card-sub">Start with an empty database</div></button>
          <button class="welcome-card" id="w-sample"><div class="welcome-card-icon">✨</div><div class="welcome-card-title">Sample Database</div><div class="welcome-card-sub">Try with sample data</div></button>
        </div>
      </div>
    </div>
  `;
  document.getElementById('w-open')?.addEventListener('click', openDatabase);
  document.getElementById('w-new')?.addEventListener('click', createNewDatabase);
  document.getElementById('w-sample')?.addEventListener('click', createSampleDB);
}

// ================================================================
//  Views: Table Grid
// ================================================================

function showTable(name) {
  S.view = 'grid';
  S.page = 0;
  S.sortCol = null;
  S.sortAsc = true;
  S.searchText = '';
  S.selectedRowID = null;
  S.editingCell = null;
  refreshSchema(name);
  loadRows();
}

function loadRows() {
  const sel = S.sidebarSelection;
  if (!sel || !db) return;
  const table = sel.name;
  const isView = S.tableSchema ? S.tableSchema.isView : false;
  const offset = S.page * S.limit;
  let where = '';
  if (S.searchText.trim()) {
    const cols = S.tableSchema ? S.tableSchema.columns : [];
    const q = S.searchText.replace(/'/g,"''");
    const clauses = cols.map(c => `"${c.name}" LIKE '%${q}%'`);
    if (clauses.length) where = ' WHERE ' + clauses.join(' OR ');
  }
  let orderBy = '';
  if (S.sortCol) orderBy = ` ORDER BY "${S.sortCol}" ${S.sortAsc ? 'ASC' : 'DESC'}`;
  try {
    const totalRes = db.exec(`SELECT COUNT(*) FROM "${table}"${where}`);
    S.totalRows = totalRes.length ? Number(totalRes[0].values[0][0]) : 0;

    // Views have no rowid, so query them plainly and synthesise identifiers.
    const sql = isView
      ? `SELECT * FROM "${table}"${where}${orderBy} LIMIT ${S.limit} OFFSET ${offset}`
      : `SELECT *, rowid AS __dvrid FROM "${table}"${where}${orderBy} LIMIT ${S.limit} OFFSET ${offset}`;
    const res = db.exec(sql);
    if (res.length) {
      const cols = res[0].columns;
      const ridIdx = cols.indexOf('__dvrid');
      S.rows = res[0].values.map((r, i) => {
        const vals = {};
        cols.forEach((c, ci) => { if (c !== '__dvrid') vals[c] = r[ci]; });
        const rowid = ridIdx >= 0 ? r[ridIdx] : (offset + i);
        return { rowid, values: vals };
      });
    } else {
      S.rows = [];
    }

    if (S.selectedRowID !== null && !S.rows.find(r => r.rowid === S.selectedRowID)) {
      S.selectedRowID = S.rows.length ? S.rows[0].rowid : null;
    }
    if (S.selectedRowID === null && S.rows.length) S.selectedRowID = S.rows[0].rowid;
    S.message = '';
  } catch (e) { S.message = e.message; }
  S.editingCell = null;
  renderGrid();
  renderRibbon();
  renderStatusBar();
}

function renderGrid() {
  const detail = document.getElementById('detail');
  if (!S.tableSchema) { detail.innerHTML = '<div class="grid-empty">Could not load table schema.</div>'; return; }
  const cols = S.tableSchema.columns;
  let html = `
    <div class="table-grid">
      <div class="grid-toolbar">
        <span class="grid-toolbar-title">📊 ${esc(S.sidebarSelection?.name||'')}${S.isView?' <span style="font-weight:400;color:#888;font-size:11px">(read-only view)</span>':''}</span>
        ${S.isView ? '' : '<button class="grid-toolbar-btn primary" id="grid-add">+ Add Record</button>'}
      </div>
  `;
  if (S.rows.length) {
    html += `
      <div class="grid-scroll">
        <table class="grid-table">
          <thead><tr>
            <th></th>
            ${cols.map(c => {
              const arrow = S.sortCol === c.name ? `<span class="sort-arrow">${S.sortAsc?'▲':'▼'}</span>` : '';
              return `<th data-col="${esc(c.name)}" title="${esc(c.type)}">${esc(c.name)}${arrow}</th>`;
            }).join('')}
          </tr></thead>
          <tbody>
    `;
    S.rows.forEach(row => {
      const isSel = row.rowid === S.selectedRowID;
      html += `<tr data-rowid="${row.rowid}" class="${isSel?'selected':''}">`;
      html += `<td data-rowid="${row.rowid}" class="row-sel-cell"><span class="row-indicator">${isSel?'►':''}</span></td>`;
      cols.forEach(c => {
        const isEditing = S.editingCell && S.editingCell.rowid === row.rowid && S.editingCell.col === c.name;
        const val = row.values[c.name];
        const display = val === null || val === undefined || val === '' ? '(no value)' : String(val);
        const cls = (val === null || val === undefined || val === '') ? 'cell-null' : '';
        if (isEditing) {
          html += `<td data-rowid="${row.rowid}" data-col="${esc(c.name)}"><input class="cell-edit-input" id="cell-edit" value="${esc(S.editingText)}"></td>`;
        } else {
          html += `<td data-rowid="${row.rowid}" data-col="${esc(c.name)}" class="${cls}">${esc(display)}</td>`;
        }
      });
      html += `</tr>`;
    });
    html += `</tbody></table></div>`;
  } else {
    html += `<div class="grid-empty">
      <div class="grid-empty-icon">📋</div>
      <div>${S.totalRows===0?(S.isView?'This view returns no rows.':'There are no records in this table yet.'):'No records match your search.'}</div>
      ${S.totalRows===0 && !S.isView ? '<button class="btn btn-primary" id="grid-add-empty">Add a record</button>' : ''}
    </div>`;
  }

  html += `<div class="grid-footer">
    <span style="font-size:11px;color:#444">Record:</span>
    <button class="nav-btn" id="nav-first" ${S.page<=0?'disabled':''}>⏮</button>
    <button class="nav-btn" id="nav-prev" ${S.page<=0?'disabled':''}>◀</button>
    <span class="grid-rec-text">${S.rows.length ? (S.page*S.limit+1)+' of '+S.totalRows : '0'}</span>
    <button class="nav-btn" id="nav-next" ${S.page*S.limit+S.rows.length>=S.totalRows?'disabled':''}>▶</button>
    <button class="nav-btn" id="nav-last" ${S.page*S.limit+S.rows.length>=S.totalRows?'disabled':''}>⏭</button>
    <span style="width:1px;height:16px;background:#ccc;margin:0 4px"></span>
    <span style="margin-left:auto"></span>
    <span style="font-size:11px;color:#888">🔍</span>
    <input type="text" class="grid-search-input" id="grid-search" placeholder="Search" value="${esc(S.searchText)}">
  </div></div>`;

  detail.innerHTML = html;
  bindGridEvents();
}

function bindGridEvents() {
  // Click on a data cell → select row + begin edit
  document.querySelectorAll('.grid-table td[data-col]').forEach(td => {
    td.addEventListener('click', e => {
      if (e.target.tagName === 'INPUT') return;
      const rowid = Number(td.dataset.rowid);
      const col = td.dataset.col;
      // Persist any in-progress edit before moving to another cell,
      // otherwise the previously typed value is silently discarded.
      if (S.editingCell && !(S.editingCell.rowid === rowid && S.editingCell.col === col)) {
        commitEdit();
      }
      S.selectedRowID = rowid;
      if (S.isView) { renderGrid(); renderRibbon(); return; }
      S.editingCell = { rowid, col };
      const row = S.rows.find(r => r.rowid === rowid);
      S.editingText = row ? (row.values[col] ?? '') : '';
      if (S.editingText === null) S.editingText = '';
      renderGrid();
      renderRibbon();
      setTimeout(() => {
        const inp = document.getElementById('cell-edit');
        if (inp) { inp.focus(); inp.select(); }
      }, 0);
    });
  });

  // Row selector click
  document.querySelectorAll('.row-sel-cell').forEach(td => {
    td.addEventListener('click', () => {
      if (S.editingCell) commitEdit();
      S.selectedRowID = Number(td.dataset.rowid);
      S.editingCell = null;
      renderGrid();
      renderRibbon();
    });
  });

  // Edit input: commit on Enter/Escape/blur. `input` keeps editingText in
  // sync with the field — without it the typed value was never saved.
  const inp = document.getElementById('cell-edit');
  if (inp) {
    inp.addEventListener('input', e => { S.editingText = e.target.value; });
    inp.addEventListener('keydown', e => {
      if (e.key === 'Enter') { e.preventDefault(); commitEdit(); }
      else if (e.key === 'Escape') { S.editingCell = null; renderGrid(); }
      else if (e.key === 'Tab') { e.preventDefault(); commitEdit(); moveEdit(e.shiftKey ? -1 : 1); }
    });
    inp.addEventListener('blur', () => {
      const r = Number(inp.dataset.rowid);
      const c = inp.dataset.col;
      setTimeout(() => {
        if (S.editingCell && S.editingCell.rowid === r && S.editingCell.col === c) commitEdit();
      }, 80);
    });
  }

  // Header sort click
  document.querySelectorAll('.grid-table th[data-col]').forEach(th => {
    th.addEventListener('click', () => {
      if (S.editingCell) commitEdit();
      const col = th.dataset.col;
      if (S.sortCol === col) S.sortAsc = !S.sortAsc;
      else { S.sortCol = col; S.sortAsc = true; }
      loadRows();
    });
  });

  // Add record
  document.getElementById('grid-add')?.addEventListener('click', addRow);
  document.getElementById('grid-add-empty')?.addEventListener('click', addRow);

  // Nav
  document.getElementById('nav-first')?.addEventListener('click', () => { S.page = 0; loadRows(); });
  document.getElementById('nav-prev')?.addEventListener('click', () => { if (S.page > 0) { S.page--; loadRows(); } });
  document.getElementById('nav-next')?.addEventListener('click', () => { if ((S.page+1)*S.limit < S.totalRows) { S.page++; loadRows(); } });
  document.getElementById('nav-last')?.addEventListener('click', () => { S.page = Math.floor((S.totalRows - 1) / S.limit); if (S.page < 0) S.page = 0; loadRows(); });

  // Search
  document.getElementById('grid-search')?.addEventListener('input', e => { S.searchText = e.target.value; debouncedReload(); });
}

function moveEdit(delta) {
  if (!S.editingCell || !S.tableSchema) return;
  const cols = S.tableSchema.columns.map(c => c.name);
  const curIdx = cols.indexOf(S.editingCell.col);
  const curRowIdx = S.rows.findIndex(r => r.rowid === S.editingCell.rowid);
  let newColIdx = curIdx + delta;
  let newRowIdx = curRowIdx;
  if (newColIdx < 0) { newColIdx = cols.length - 1; newRowIdx = Math.max(0, curRowIdx - 1); }
  if (newColIdx >= cols.length) { newColIdx = 0; newRowIdx = Math.min(S.rows.length - 1, curRowIdx + 1); }
  if (newRowIdx < 0 || newRowIdx >= S.rows.length) return;
  const row = S.rows[newRowIdx];
  S.editingCell = { rowid: row.rowid, col: cols[newColIdx] };
  S.editingText = row.values[cols[newColIdx]] ?? '';
  if (S.editingText === null) S.editingText = '';
  renderGrid();
  setTimeout(() => { const el = document.getElementById('cell-edit'); if (el) { el.focus(); el.select(); } }, 0);
}

function commitEdit() {
  if (!S.editingCell || !db) return;
  if (S.isView) { S.editingCell = null; return; }
  const { rowid, col } = S.editingCell;
  const row = S.rows.find(r => r.rowid === rowid);
  if (!row) { S.editingCell = null; return; }
  const oldVal = row.values[col];
  let newVal = S.editingText;
  if (newVal === '' || newVal === null) newVal = null;
  if (String(oldVal) === String(newVal)) { S.editingCell = null; renderGrid(); return; }
  try {
    const colType = S.tableSchema?.columns.find(c => c.name === col)?.type?.toUpperCase() || '';
    let stmt;
    if (newVal === null) {
      stmt = `UPDATE "${S.sidebarSelection.name}" SET "${col}" = NULL WHERE rowid = ?`;
      db.run(stmt, [rowid]);
    } else {
      const typed = inferType(newVal, colType);
      if (typed === null) {
        stmt = `UPDATE "${S.sidebarSelection.name}" SET "${col}" = ? WHERE rowid = ?`;
        db.run(stmt, [newVal, rowid]);
      } else {
        stmt = `UPDATE "${S.sidebarSelection.name}" SET "${col}" = ? WHERE rowid = ?`;
        db.run(stmt, [typed, rowid]);
      }
    }
    row.values[col] = newVal === null ? null : (newVal === '' ? null : (inferType(newVal, colType) ?? newVal));
    saveToDisk();
    S.message = 'Record updated';
  } catch (e) { S.message = 'Update failed: ' + e.message; }
  S.editingCell = null;
  renderGrid();
  renderStatusBar();
}

function inferType(val, colType) {
  if (val === null || val === '') return null;
  if (colType.includes('INT')) { const n = Number(val); return Number.isFinite(n) && String(n) === val.trim() ? n : val; }
  if (colType.includes('REAL') || colType.includes('FLOAT') || colType.includes('DOUBLE')) { const n = Number(val); return Number.isFinite(n) ? n : val; }
  if (colType.includes('BOOL')) { const v = val.trim().toLowerCase(); if (['1','true','yes','y','t'].includes(v)) return 1; if (['0','false','no','n','f'].includes(v)) return 0; }
  return val;
}

function addRow() {
  if (!db || !S.tableSchema) return;
  if (S.isView) { S.message = 'Views are read-only'; renderStatusBar(); return; }
  const table = S.sidebarSelection?.name;
  try {
    // Skip primary-key columns (let SQLite assign the key / default) and only
    // seed columns that are NOT NULL with no default, so inserts never fail
    // with a constraint error on the sample schema.
    const insCols = [];
    const vals = [];
    for (const c of S.tableSchema.columns) {
      if (c.pk) continue;
      if (c.notnull && (c.dflt === null || c.dflt === undefined)) {
        const t = (c.type || '').toUpperCase();
        insCols.push(c.name);
        if (t.includes('INT') || t.includes('REAL') || t.includes('FLOA') || t.includes('DOUB') || t.includes('NUM')) vals.push(0);
        else vals.push('');
      }
    }
    if (insCols.length) {
      db.run(`INSERT INTO "${table}" (${insCols.map(c=>'"'+c+'"').join(',')}) VALUES (${insCols.map(()=>'?').join(',')})`, vals);
    } else {
      db.run(`INSERT INTO "${table}" DEFAULT VALUES`);
    }
    const rowid = db.exec('SELECT last_insert_rowid()')[0].values[0][0];
    saveToDisk();
    S.selectedRowID = Number(rowid);
    S.page = Math.floor((S.totalRows) / S.limit);
    loadRows();
    S.message = 'Record added';
    renderStatusBar();
  } catch (e) { S.message = 'Add failed: ' + e.message; renderStatusBar(); }
}

function duplicateRow() {
  if (!db || !S.selectedRowID || !S.tableSchema || !S.sidebarSelection) return;
  if (S.isView) { S.message = 'Views are read-only'; renderStatusBar(); return; }
  const table = S.sidebarSelection.name;
  try {
    const srcRow = S.rows.find(r => r.rowid === S.selectedRowID);
    if (!srcRow) return;
    // Omit primary-key columns so the database assigns a fresh key.
    const pkCols = new Set(S.tableSchema.pkCols);
    const insCols = S.tableSchema.columns.map(c => c.name).filter(c => !pkCols.has(c));
    const vals = insCols.map(c => srcRow.values[c] ?? null);
    if (!insCols.length) { S.message = 'Nothing to duplicate'; renderStatusBar(); return; }
    const placeholders = insCols.map(() => '?').join(',');
    db.run(`INSERT INTO "${table}" (${insCols.map(c=>'"'+c+'"').join(',')}) VALUES (${placeholders})`, vals);
    const rowid = db.exec('SELECT last_insert_rowid()')[0].values[0][0];
    saveToDisk();
    S.selectedRowID = Number(rowid);
    loadRows();
    S.message = 'Record duplicated';
    renderStatusBar();
  } catch (e) { S.message = 'Duplicate failed: ' + e.message; renderStatusBar(); }
}

function deleteRow() {
  if (!db || !S.selectedRowID || !S.sidebarSelection) return;
  if (S.isView) { S.message = 'Views are read-only'; renderStatusBar(); return; }
  showAlert('Delete row?', 'This will permanently delete the selected record.', [
    { label: 'Delete', primary: true, fn: () => {
      try {
        db.run(`DELETE FROM "${S.sidebarSelection.name}" WHERE rowid = ?`, [S.selectedRowID]);
        saveToDisk();
        S.selectedRowID = null;
        loadRows();
        S.message = 'Record deleted';
        renderStatusBar();
      } catch (e) { S.message = 'Delete failed: ' + e.message; renderStatusBar(); }
    }},
    { label: 'Cancel' },
  ]);
}

function reloadCurrentTable() { if (S.sidebarSelection?.name) loadRows(); }

function clearSortFilter() {
  S.searchText = '';
  S.sortCol = null;
  S.sortAsc = true;
  loadRows();
}

// ================================================================
//  Views: Table Designer
// ================================================================

function showDesigner() {
  S.view = 'designer';
  S.designer = { tableName: '', columns: [] };
  renderDesigner();
}

function renderDesigner() {
  const detail = document.getElementById('detail');
  const d = S.designer;
  let html = `
    <div class="designer">
      <h2>Design a Table</h2>
      <p class="sub">Point-and-click — no SQL required. We generate the SQL for you.</p>

      <label class="field-label">Table name</label>
      <input type="text" class="text-field" id="des-name" value="${esc(d.tableName)}" placeholder="e.g. customers" style="width:320px;margin-bottom:16px">

      <div class="designer-section">
        <h3>📋 Columns <span style="margin-left:auto"><button class="btn" id="des-sample" style="font-size:10px">✨ Sample columns</button></span></h3>
        <table class="col-table">
          <thead><tr><th>Name</th><th>Type</th><th>PK</th><th>Auto</th><th>Not Null</th><th>Unique</th><th>Default</th><th>References</th><th></th></tr></thead>
          <tbody id="des-cols">
  `;
  const targets = fkTargets();
  d.columns.forEach((col, i) => {
    html += `<tr>
      <td><input type="text" value="${esc(col.name)}" data-i="${i}" data-f="name" placeholder="col_name"></td>
      <td><select data-i="${i}" data-f="type">
        ${['TEXT','INTEGER','REAL','NUMERIC','BOOLEAN','DATE','DATETIME','BLOB','JSON'].map(t => `<option${col.type===t?' selected':''}>${t}</option>`).join('')}
      </select></td>
      <td style="text-align:center"><input type="checkbox" ${col.isPK?'checked':''} data-i="${i}" data-f="pk"></td>
      <td style="text-align:center"><input type="checkbox" ${col.isAuto?'checked':''} data-i="${i}" data-f="auto" ${col.isPK&&col.type==='INTEGER'?'':'disabled'}></td>
      <td style="text-align:center"><input type="checkbox" ${col.notNull?'checked':''} data-i="${i}" data-f="notnull"></td>
      <td style="text-align:center"><input type="checkbox" ${col.unique?'checked':''} data-i="${i}" data-f="unique"></td>
      <td><input type="text" value="${esc(col.defaultValue||'')}" data-i="${i}" data-f="default" placeholder="(none)" style="width:100px"></td>
      <td><select data-i="${i}" data-f="fk">
        <option value="">—</option>
        ${targets.map(t => { const v = t.table + '.' + t.column; return `<option value="${esc(v)}"${col.fk===v?' selected':''}>${esc(t.table)}.${esc(t.column)}</option>`; }).join('')}
      </select></td>
      <td><button class="remove-btn" data-i="${i}">✕</button></td>
    </tr>`;
  });
  html += `</tbody></table>
    <div style="margin-top:8px">
      <button class="btn" id="des-add-col">+ Add Column</button>
      <span style="font-size:10px;color:#888;margin-left:8px">Tip: type a column name like "email" and we suggest the right type.</span>
    </div>
  </div>

  <div class="designer-section">
    <h3>📄 SQL preview</h3>
    <div class="sql-preview" id="des-preview">${highlightSQL(generatePreviewSQL())}</div>
    <div style="display:flex;justify-content:flex-end;gap:8px;margin-top:12px">
      <button class="btn" id="des-reset">Clear</button>
      <button class="btn btn-primary" id="des-create" ${d.columns.length===0||!d.tableName.trim()?'disabled':''}>Create Table</button>
    </div>
  </div>
  </div>`;

  detail.innerHTML = html;
  bindDesignerEvents();
}

function bindDesignerEvents() {
  const d = S.designer;
  document.getElementById('des-name')?.addEventListener('input', e => { d.tableName = e.target.value; updatePreview(); });
  document.getElementById('des-add-col')?.addEventListener('click', () => { d.columns.push(emptyCol()); renderDesigner(); });
  document.getElementById('des-sample')?.addEventListener('click', sampleColumns);
  document.getElementById('des-reset')?.addEventListener('click', () => { d.tableName = ''; d.columns = []; renderDesigner(); });
  document.getElementById('des-create')?.addEventListener('click', createTableFromDesign);

  document.querySelectorAll('.col-table input[data-f],.col-table select[data-f]').forEach(el => {
    const i = Number(el.dataset.i);
    const f = el.dataset.f;
    el.addEventListener('input', () => {
      if (f === 'pk') { d.columns[i].isPK = el.checked; if (el.checked) d.columns[i].typeTouched = true; }
      else if (f === 'auto') { d.columns[i].isAuto = el.checked; }
      else if (f === 'notnull') { d.columns[i].notNull = el.checked; }
      else if (f === 'unique') { d.columns[i].unique = el.checked; }
      else if (f === 'type') { d.columns[i].type = el.value; d.columns[i].typeTouched = true; }
      else if (f === 'fk') { d.columns[i].fk = el.value; }
      else {
        d.columns[i][f] = el.value;
        // Suggest a type from the column name until the user picks one.
        if (f === 'name' && !d.columns[i].typeTouched) {
          const suggested = suggestType(el.value);
          d.columns[i].type = suggested;
          const typeSel = document.querySelector(`.col-table select[data-i="${i}"][data-f="type"]`);
          if (typeSel) typeSel.value = suggested;
        }
      }
      updatePreview();
    });
  });

  document.querySelectorAll('.remove-btn[data-i]').forEach(btn => {
    btn.addEventListener('click', () => { d.columns.splice(Number(btn.dataset.i), 1); renderDesigner(); });
  });
}

function emptyCol() {
  return { name: '', type: 'TEXT', isPK: false, isAuto: false, notNull: false, unique: false, defaultValue: '', fk: '', typeTouched: false };
}

/// Guesses a column type from its name, mirroring the macOS designer.
function suggestType(name) {
  const n = String(name || '').toLowerCase();
  if (!n) return 'TEXT';
  if (n.endsWith('id') || n.includes('_id') || n === 'id' || n.startsWith('num') || n.startsWith('count')
      || n.startsWith('qty') || n.startsWith('quantity') || n.startsWith('price')
      || n.startsWith('cost') || n.startsWith('amount') || n.startsWith('total')
      || n.includes('year') || n.includes('age') || n.startsWith('rating')) {
    if (n === 'id' || n.endsWith('_id') || n.startsWith('num') || n.startsWith('count')
        || n.startsWith('qty') || n.startsWith('quantity')) return 'INTEGER';
    if (n.startsWith('price') || n.startsWith('cost') || n.startsWith('amount')
        || n.startsWith('total') || n.startsWith('rating')) return 'REAL';
    return 'INTEGER';
  }
  if (n.includes('date') || n.includes('time') || n.includes('dob') || n.includes('created') || n.includes('updated')) {
    return 'DATETIME';
  }
  if (n.startsWith('is') || n.startsWith('has') || n.includes('active') || n.includes('enabled')
      || n.includes('flag') || n.includes('bool')) {
    return 'BOOLEAN';
  }
  return 'TEXT';
}

/// Primary-key columns of every existing table, offered as FK targets.
function fkTargets() {
  if (!db) return [];
  const out = [];
  for (const o of S.objects) {
    if (o.kind !== 'table') continue;
    try {
      const info = db.exec(`PRAGMA table_info('${o.name.replace(/'/g, "''")}')`);
      if (!info.length) continue;
      const pkCols = info[0].values.filter(r => Number(r[5]) > 0).map(r => String(r[1]));
      const cols = pkCols.length ? pkCols : info[0].values.map(r => String(r[1]));
      for (const c of cols) out.push({ table: o.name, column: c });
    } catch {}
  }
  return out;
}

function sampleColumns() {
  S.designer.tableName = S.designer.tableName || 'new_table';
  S.designer.columns = [
    { name: 'id', type: 'INTEGER', isPK: true, isAuto: true, notNull: false, unique: false, defaultValue: '' },
    { name: 'name', type: 'TEXT', isPK: false, isAuto: false, notNull: false, unique: false, defaultValue: '' },
    { name: 'email', type: 'TEXT', isPK: false, isAuto: false, notNull: false, unique: false, defaultValue: '' },
    { name: 'is_active', type: 'BOOLEAN', isPK: false, isAuto: false, notNull: false, unique: false, defaultValue: '' },
    { name: 'created_at', type: 'DATETIME', isPK: false, isAuto: false, notNull: false, unique: false, defaultValue: '' },
  ];
  renderDesigner();
}

function updatePreview() {
  const el = document.getElementById('des-preview');
  if (el) el.innerHTML = highlightSQL(generatePreviewSQL());
  const btn = document.getElementById('des-create');
  if (btn) btn.disabled = S.designer.columns.length === 0 || !S.designer.tableName.trim();
}

function generatePreviewSQL() {
  const d = S.designer;
  if (!d.columns.length) {
    return d.tableName.trim()
      ? `CREATE TABLE "${d.tableName.trim()}" (\n  -- add columns…\n)`
      : '-- Add at least one column to your table.';
  }
  const parts = d.columns.map(col => columnClause(col));
  const pks = d.columns.filter(c => c.isPK);
  const tablePKs = pks.filter(c => !(c.isAuto && c.type === 'INTEGER'));
  if (tablePKs.length) parts.push(`PRIMARY KEY (${tablePKs.map(c=>'"'+c.name+'"').join(', ')})`);
  return `CREATE TABLE "${d.tableName.trim()}" (\n  ${parts.join(',\n  ')}\n)`;
}

function columnClause(col) {
  let s = `"${col.name}" ${col.type}`;
  if (col.isPK && col.isAuto && col.type === 'INTEGER') {
    s += ' PRIMARY KEY AUTOINCREMENT';
  } else {
    if (col.notNull) s += ' NOT NULL';
    if (col.unique && !col.isPK) s += ' UNIQUE';
    const def = (col.defaultValue || '').trim();
    if (def) s += ` DEFAULT ${def}`;
  }
  const fk = (col.fk || '').trim();
  if (fk) {
    const [tbl, colName] = fk.split('.');
    if (tbl && colName) s += ` REFERENCES "${tbl}"("${colName}")`;
  }
  return s;
}

function createTableFromDesign() {
  if (!db) return;
  const d = S.designer;
  const name = d.tableName.trim();
  if (!name || !d.columns.length) return;
  try {
    db.run(generatePreviewSQL());
    saveToDisk();
    refreshObjects();
    toast(`Table "${name}" created`);
    selectSidebar({ type: 'table', name });
  } catch (e) { toast('Create failed: ' + e.message, 'error'); }
}

// ================================================================
//  Views: SQL Query Editor
// ================================================================

function showQuery() {
  S.view = 'query';
  renderQuery();
}

function renderQuery() {
  const detail = document.getElementById('detail');
  let html = `
    <div class="query-view">
      <div style="padding:6px 12px;border-bottom:1px solid #e5e5e5;display:flex;align-items:center;gap:8px">
        <span style="font-size:12px;font-weight:600">⌨️ SQL Query</span>
        <span style="font-size:10px;color:#888;margin-left:auto">SQL View</span>
      </div>
      <div class="query-split">
        <div class="query-left">
          <div style="padding:6px 12px;font-size:12px;font-weight:600;display:flex;gap:6px;align-items:center">
            <span>SQL Statement</span>
            <span style="margin-left:auto">
              <button class="btn" id="q-samples" style="font-size:10px">💡 Samples</button>
              <button class="btn" id="q-clear" style="font-size:10px">Clear</button>
            </span>
          </div>
          <textarea class="query-textarea" id="q-editor" spellcheck="false">${esc(S.query.sql)}</textarea>
          <div class="query-toolbar">
            <button class="btn btn-primary" id="q-run">▶ Run</button>
            <span style="margin-left:auto"><button class="btn" id="q-history" style="font-size:10px">🕐 History</button></span>
          </div>
          <div class="query-status ${S.query.error?'error':S.query.result?'success':''}" id="q-status">${S.query.error?esc(S.query.error):S.query.result?(S.query.result.isDataQuery?S.query.result.rows.length+' row(s) returned':'Done — '+S.query.result.rowCount+' row(s) affected'):'Run a query to see results. Tip: Ctrl+Enter to run.'}</div>
        </div>
        <div class="query-right">
          <div class="query-right-header">Results</div>
          <div class="query-results" id="q-results">${renderResultGrid()}</div>
        </div>
      </div>
    </div>`;

  detail.innerHTML = html;

  document.getElementById('q-run')?.addEventListener('click', runQuery);
  document.getElementById('q-clear')?.addEventListener('click', () => { S.query.sql = ''; S.query.result = null; S.query.error = null; renderQuery(); });
  document.getElementById('q-history')?.addEventListener('click', showHistory);
  document.getElementById('q-samples')?.addEventListener('click', showSamples);

  const editor = document.getElementById('q-editor');
  if (editor) {
    editor.addEventListener('input', e => { S.query.sql = e.target.value; });
    editor.addEventListener('keydown', e => {
      if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); runQuery(); }
    });
  }
}

function renderResultGrid() {
  const r = S.query.result;
  if (!r || !r.isDataQuery || !r.rows.length) {
    if (!r) return '<div style="display:flex;align-items:center;justify-content:center;height:100%;color:#aaa">📋<br>Results will appear here</div>';
    return '';
  }
  let html = `<table class="result-grid-table"><thead><tr>${r.columns.map(c=>'<th>'+esc(c)+'</th>').join('')}</tr></thead><tbody>`;
  r.rows.forEach(row => {
    html += '<tr>' + r.columns.map(c => {
      const v = row[c];
      const d = v === null ? '' : String(v);
      const cls = v === null ? 'cell-null' : '';
      return `<td class="${cls}">${esc(d)}</td>`;
    }).join('') + '</tr>';
  });
  html += '</tbody></table>';
  return html;
}

function runQuery() {
  if (!db) { S.query.error = 'No database open'; renderQuery(); return; }
  const sql = S.query.sql.trim();
  if (!sql) return;
  S.query.error = null;
  S.query.result = null;
  try {
    const statements = splitSQL(sql);
    let lastResult = null;
    statements.forEach(stmt => {
      const res = db.exec(stmt);
      if (res.length && res[0].columns.length) {
        const cols = res[0].columns;
        const rows = res[0].values.map(r => {
          const obj = {};
          cols.forEach((c,i) => obj[c] = r[i]);
          return obj;
        });
        lastResult = { columns: cols, rows, rowCount: 0, isDataQuery: true };
      } else {
        const changes = db.getRowsModified();
        lastResult = { columns: [], rows: [], rowCount: changes, isDataQuery: false };
      }
    });
    S.query.result = lastResult;
    if (sql && !S.query.history.includes(sql)) S.query.history.unshift(sql);
    if (S.query.history.length > 50) S.query.history.length = 50;
    persistQueryHistory();
  } catch (e) {
    S.query.error = e.message;
  }
  renderQuery();
}

function splitSQL(sql) {
  const statements = [];
  let current = '';
  let inSingle = false, inDouble = false, inLineComment = false;
  for (let i = 0; i < sql.length; i++) {
    const c = sql[i];
    const next = i + 1 < sql.length ? sql[i+1] : '';
    if (inLineComment) { if (c === '\n') inLineComment = false; current += c; continue; }
    if (inSingle) {
      current += c;
      if (c === "'" && next === "'") { current += "'"; i++; }
      else if (c === "'") inSingle = false;
      continue;
    }
    if (inDouble) { current += c; if (c === '"') inDouble = false; continue; }
    if (c === '-' && next === '-') { inLineComment = true; current += '--'; i++; continue; }
    if (c === ';') { const t = current.trim(); if (t && !t.split('\n').every(l => l.trim().startsWith('--'))) statements.push(t); current = ''; continue; }
    if (c === "'") { inSingle = true; current += c; continue; }
    if (c === '"') { inDouble = true; current += c; continue; }
    current += c;
  }
  const t = current.trim();
  if (t && !t.split('\n').every(l => l.trim().startsWith('--'))) statements.push(t);
  return statements;
}

function showSamples() {
  showAlert('Sample queries', '', [
    { label: 'Select all customers', fn: () => { S.query.sql = 'SELECT * FROM customers LIMIT 50;'; renderQuery(); }},
    { label: 'Count per product', fn: () => { S.query.sql = "SELECT p.name, SUM(o.quantity) AS total_sold\nFROM orders o\nJOIN products p ON p.id = o.product_id\nGROUP BY p.name\nORDER BY total_sold DESC"; renderQuery(); }},
    { label: 'Close' },
  ]);
}

function showHistory() {
  if (!S.query.history.length) return;
  const root = document.getElementById('modal-root');
  root.innerHTML = `
    <div class="history-overlay" id="hist-overlay">
      <div class="history-sheet">
        <h3>Query History <span style="font-size:10px;color:#888;font-weight:400;margin-left:8px">${S.query.history.length} saved</span></h3>
        <div class="history-list">${S.query.history.map((h,i) =>
          `<div class="history-item" data-i="${i}">${esc(h)}</div>`
        ).join('')}</div>
        <div class="history-footer"><button class="btn" id="hist-close">Cancel</button></div>
      </div>
    </div>`;
  document.getElementById('hist-overlay')?.addEventListener('click', e => {
    if (e.target.id === 'hist-overlay') root.innerHTML = '';
  });
  document.getElementById('hist-close')?.addEventListener('click', () => { root.innerHTML = ''; });
  document.querySelectorAll('.history-item[data-i]').forEach(el => {
    el.addEventListener('click', () => {
      S.query.sql = S.query.history[Number(el.dataset.i)];
      root.innerHTML = '';
      renderQuery();
    });
  });
}

// ================================================================
//  Actions
// ================================================================

async function openDatabase() {
  const path = await celistdb.openDatabaseDialog();
  if (!path) return;
  await loadDB(path);
  S.sidebarSelection = null;
  renderWelcome();
  renderNavPane();
  toast('Database opened');
}

async function createNewDatabase() {
  const path = await celistdb.newDatabaseDialog();
  if (!path) return;
  await newDB(path);
  S.sidebarSelection = null;
  renderWelcome();
  renderNavPane();
  toast('Database created');
}

async function createSampleDB() {
  const path = await celistdb.createSampleDialog();
  if (!path) return;
  dbPath = path;
  db = new SQL.Database();
  // Create tables
  db.run(`CREATE TABLE customers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT,
    city TEXT,
    is_vip INTEGER DEFAULT 0
  )`);
  db.run(`CREATE TABLE products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    sku TEXT,
    price REAL,
    in_stock INTEGER DEFAULT 1
  )`);
  db.run(`CREATE TABLE orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    product_id INTEGER NOT NULL REFERENCES products(id),
    quantity INTEGER DEFAULT 1,
    order_date TEXT
  )`);
  // Seed data
  db.run("INSERT INTO customers (name,email,city,is_vip) VALUES ('Alice Johnson','alice@example.com','Springfield',1),('Bob Smith','bob@example.com','Shelbyville',0),('Carol White','carol@example.com','Springfield',0),('Dave Brown','dave@example.com','Capital City',1)");
  db.run("INSERT INTO products (name,sku,price,in_stock) VALUES ('Laptop','ELEC-001',999.99,10),('Mouse','ELEC-002',29.99,150),('Desk','FURN-001',249.99,8),('Notebook','STATION-001',4.99,200)");
  db.run("INSERT INTO orders (customer_id,product_id,quantity,order_date) VALUES (1,1,1,'2025-01-15'),(1,2,2,'2025-01-15'),(2,3,1,'2025-02-01'),(3,4,5,'2025-02-10'),(4,1,1,'2025-03-01'),(4,2,3,'2025-03-01')");
  saveToDisk();
  refreshObjects();
  updateDBName();
  S.sidebarSelection = null;
  renderWelcome();
  renderNavPane();
  toast('Sample database created');
}

function closeDatabase() {
  db = null;
  dbPath = null;
  S.sidebarSelection = null;
  S.objects = [];
  S.rowCounts = {};
  S.tableSchema = null;
  S.isView = false;
  S.rows = [];
  S.selectedRowID = null;
  S.message = '';
  renderWelcome();
  renderNavPane();
  renderRibbon();
  document.getElementById('db-name').textContent = '';
}

// ================================================================
//  CSV import / export
// ================================================================

async function exportCSV() {
  if (!db) { toast('Open a database first', 'error'); return; }
  let columns = [];
  let rows = [];
  if (S.view === 'query' && S.query.result && S.query.result.isDataQuery) {
    columns = S.query.result.columns;
    rows = S.query.result.rows.map(r => columns.map(c => r[c]));
  } else if (S.view === 'grid' && S.sidebarSelection?.name) {
    const res = db.exec(`SELECT * FROM "${S.sidebarSelection.name}"`);
    if (res.length) { columns = res[0].columns; rows = res[0].values; }
  } else {
    toast('Open a table or run a query first', 'error');
    return;
  }
  if (!columns.length) { toast('Nothing to export', 'error'); return; }
  const path = await celistdb.exportCSVDialog();
  if (!path) return;
  try {
    const csv = toCSV(columns, rows);
    await celistdb.writeFile(path, Array.from(new TextEncoder().encode(csv)));
    toast(`Exported ${rows.length} row(s)`);
  } catch (e) { toast('Export failed: ' + e.message, 'error'); }
}

async function importCSV() {
  if (!db) { toast('Open or create a database first', 'error'); return; }
  const path = await celistdb.importCSVDialog();
  if (!path) return;
  try {
    const data = await celistdb.readFile(path);
    const text = new TextDecoder('utf-8').decode(new Uint8Array(data.bytes));
    const { headers, rows } = parseCSV(text);
    if (!headers.length) { toast('CSV appears to be empty', 'error'); return; }
    const base = path.replace(/\\/g, '/').split('/').pop().replace(/\.[^.]+$/, '');
    let table = sanitizeIdent(base) || 'imported';
    // Ensure the name is unique.
    let n = 2;
    const existing = new Set(S.objects.map(o => o.name));
    while (existing.has(table)) table = sanitizeIdent(base) + '_' + (n++);

    const cols = headers.map((h, i) => `"${sanitizeIdent(h) || 'col' + (i + 1)}" TEXT`);
    db.run(`CREATE TABLE "${table}" (${cols.join(', ')})`);
    const stmt = db.prepare(`INSERT INTO "${table}" VALUES (${headers.map(() => '?').join(',')})`);
    for (const r of rows) {
      stmt.run(headers.map((_, i) => (r[i] !== undefined ? r[i] : null)));
    }
    stmt.free();
    saveToDisk();
    refreshObjects();
    toast(`Imported ${rows.length} row(s) into "${table}"`);
    selectSidebar({ type: 'table', name: table });
  } catch (e) { toast('Import failed: ' + e.message, 'error'); }
}

// ---- JSON import --------------------------------------------------

async function importJSON() {
  if (!db) { toast('Open or create a database first', 'error'); return; }
  const path = await celistdb.importJSONDialog();
  if (!path) return;
  try {
    const data = await celistdb.readFile(path);
    const text = new TextDecoder('utf-8').decode(new Uint8Array(data.bytes));
    const parsed = JSON.parse(text);
    // Accept a top-level array, { rows: [...] }, { data: [...] }, or a single object.
    let arr;
    if (Array.isArray(parsed)) arr = parsed;
    else if (parsed && Array.isArray(parsed.rows)) arr = parsed.rows;
    else if (parsed && Array.isArray(parsed.data)) arr = parsed.data;
    else if (parsed && typeof parsed === 'object') arr = [parsed];
    else arr = [];
    arr = arr.filter(o => o && typeof o === 'object' && !Array.isArray(o));
    if (!arr.length) { toast('JSON contains no objects to import', 'error'); return; }

    // Union of all keys, in first-seen order.
    const headers = [];
    for (const obj of arr) for (const k of Object.keys(obj)) if (!headers.includes(k)) headers.push(k);
    if (!headers.length) { toast('JSON objects have no fields', 'error'); return; }

    const base = path.replace(/\\/g, '/').split('/').pop().replace(/\.[^.]+$/, '');
    let table = sanitizeIdent(base) || 'imported_json';
    let n = 2;
    const existing = new Set(S.objects.map(o => o.name));
    while (existing.has(table)) table = sanitizeIdent(base) + '_' + (n++);

    const cols = headers.map((h, i) => `"${sanitizeIdent(h) || 'col' + (i + 1)}" TEXT`);
    db.run(`CREATE TABLE "${table}" (${cols.join(', ')})`);
    const stmt = db.prepare(`INSERT INTO "${table}" VALUES (${headers.map(() => '?').join(',')})`);
    for (const obj of arr) {
      stmt.run(headers.map(h => {
        const v = obj[h];
        if (v === undefined || v === null) return null;
        if (typeof v === 'object') return JSON.stringify(v);
        if (typeof v === 'boolean') return v ? 1 : 0;
        return v;
      }));
    }
    stmt.free();
    saveToDisk();
    refreshObjects();
    toast(`Imported ${arr.length} row(s) into "${table}"`);
    selectSidebar({ type: 'table', name: table });
  } catch (e) { toast('JSON import failed: ' + e.message, 'error'); }
}

// ---- Relationships + backup ---------------------------------------

function collectRelationships() {
  const rels = [];
  if (!db) return rels;
  for (const o of S.objects) {
    if (o.kind !== 'table') continue;
    try {
      const info = db.exec(`PRAGMA foreign_key_list('${o.name.replace(/'/g, "''")}')`);
      if (!info.length) continue;
      for (const r of info[0].values) {
        rels.push({ fromTable: String(o.name), fromCol: String(r[3]), toTable: String(r[2]), toCol: String(r[4]) });
      }
    } catch {}
  }
  return rels;
}

function showRelationships() {
  if (!db) { toast('Open a database first', 'error'); return; }
  const rels = collectRelationships();
  const root = document.getElementById('modal-root');
  const body = rels.length
    ? `<table class="rel-table"><thead><tr><th>Table</th><th>Column</th><th></th><th>References</th><th>Column</th></tr></thead><tbody>${
        rels.map(r => `<tr><td>${esc(r.fromTable)}</td><td>${esc(r.fromCol)}</td><td class="rel-arrow">➜</td><td>${esc(r.toTable)}</td><td>${esc(r.toCol)}</td></tr>`).join('')
      }</tbody></table>`
    : `<p class="rel-empty">No foreign-key relationships have been defined in this database.<br><br>Tip: create one by adding a “References” target to a column in the Table Designer.</p>`;
  root.innerHTML = `
    <div class="history-overlay" id="rel-overlay">
      <div class="history-sheet rel-sheet">
        <h3>🔗 Relationships <span style="font-size:10px;color:#888;font-weight:400;margin-left:8px">${rels.length} link${rels.length === 1 ? '' : 's'}</span></h3>
        <div class="history-list">${body}</div>
        <div class="history-footer"><button class="btn" id="rel-close">Close</button></div>
      </div>
    </div>`;
  document.getElementById('rel-overlay')?.addEventListener('click', e => { if (e.target.id === 'rel-overlay') root.innerHTML = ''; });
  document.getElementById('rel-close')?.addEventListener('click', () => { root.innerHTML = ''; });
}

async function backupDatabase() {
  if (!db || !dbPath) { toast('Open a database first', 'error'); return; }
  const path = await celistdb.backupDatabaseDialog(dbPath);
  if (!path) return;
  try {
    await celistdb.writeFile(path, Array.from(db.export()));
    toast('Backup saved');
  } catch (e) { toast('Backup failed: ' + e.message, 'error'); }
}

function toCSV(columns, rows) {
  const cell = v => {
    if (v === null || v === undefined) return '';
    const s = String(v);
    return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  let out = columns.map(cell).join(',') + '\n';
  for (const row of rows) out += row.map(cell).join(',') + '\n';
  return out;
}

/// Minimal RFC-4180 CSV parser: quoted fields, escaped quotes, CRLF/LF.
function parseCSV(text) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else inQuotes = false;
      } else field += c;
    } else if (c === '"') {
      inQuotes = true;
    } else if (c === ',') {
      row.push(field); field = '';
    } else if (c === '\n') {
      row.push(field); rows.push(row); row = []; field = '';
    } else if (c === '\r') {
      // ignore
    } else {
      field += c;
    }
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  const nonEmpty = rows.filter(r => r.some(x => x !== ''));
  if (!nonEmpty.length) return { headers: [], rows: [] };
  return { headers: nonEmpty[0], rows: nonEmpty.slice(1) };
}

function sanitizeIdent(s) {
  return String(s || '').trim().replace(/[^\w]/g, '_').replace(/^(\d)/, 'c$1');
}

// ================================================================
//  SQL syntax highlighting
// ================================================================

function highlightSQL(sql) {
  if (!sql) return '';
  const keywords = ['SELECT','FROM','WHERE','AND','OR','NOT','INSERT','INTO','VALUES','UPDATE','SET',
    'DELETE','CREATE','TABLE','DROP','ALTER','INDEX','VIEW','PRIMARY','KEY','AUTOINCREMENT',
    'NOT','NULL','DEFAULT','UNIQUE','REFERENCES','CHECK','ON','AS','IS','IN','LIKE','BETWEEN',
    'ORDER','BY','GROUP','HAVING','LIMIT','OFFSET','JOIN','INNER','LEFT','RIGHT','OUTER','CROSS',
    'UNION','ALL','EXISTS','CASE','WHEN','THEN','ELSE','END','COUNT','SUM','AVG','MIN','MAX',
    'DISTINCT','ASC','DESC','IF','REPLACE','PRAGMA'];
  let result = '';
  let i = 0;
  while (i < sql.length) {
    if (sql[i] === '-' && sql[i+1] === '-') {
      const end = sql.indexOf('\n', i);
      const cmt = end === -1 ? sql.slice(i) : sql.slice(i, end);
      result += `<span class="sql-cmt">${esc(cmt)}</span>`;
      i += cmt.length;
    } else if (sql[i] === "'") {
      let j = i + 1;
      while (j < sql.length) { if (sql[j] === "'" && sql[j+1] === "'") j += 2; else if (sql[j] === "'") break; else j++; }
      result += `<span class="sql-str">${esc(sql.slice(i, j+1))}</span>`;
      i = j + 1;
    } else if (sql[i] === '"') {
      let j = i + 1;
      while (j < sql.length && sql[j] !== '"') j++;
      result += `<span class="sql-id">${esc(sql.slice(i, j+1))}</span>`;
      i = j + 1;
    } else if (/[a-zA-Z_]/.test(sql[i])) {
      let j = i;
      while (j < sql.length && /[a-zA-Z_0-9]/.test(sql[j])) j++;
      const word = sql.slice(i, j);
      if (keywords.includes(word.toUpperCase())) result += `<span class="sql-kw">${esc(word)}</span>`;
      else result += esc(word);
      i = j;
    } else { result += esc(sql[i]); i++; }
  }
  return result;
}

// ================================================================
//  Helpers
// ================================================================

function esc(s) {
  if (s === null || s === undefined) return '';
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}

let reloadTimer = null;
function debouncedReload() {
  clearTimeout(reloadTimer);
  reloadTimer = setTimeout(loadRows, 300);
}

function renderStatusBar() {
  const left = document.getElementById('status-left');
  const right = document.getElementById('status-right');
  if (left) left.textContent = S.objects.length ? `${S.objects.filter(o=>o.kind==='table').length} tables, ${S.objects.filter(o=>o.kind==='view').length} views` : '';
  if (right) right.querySelector('#status-message').textContent = S.message || '';
}

function toast(msg, type = 'success') {
  const root = document.getElementById('toast-root');
  const el = document.createElement('div');
  el.className = 'toast ' + type;
  el.textContent = msg;
  root.appendChild(el);
  setTimeout(() => el.remove(), 3000);
}

function showAlert(title, message, buttons) {
  const root = document.getElementById('modal-root');
  const btns = buttons || [{ label: 'OK' }];
  root.innerHTML = `
    <div class="alert-overlay" id="alert-overlay">
      <div class="alert-box">
        <h4>${esc(title)}</h4>
        ${message ? `<p style="white-space:pre-wrap">${esc(message)}</p>` : ''}
        <div class="btn-row">${btns.map((b,i) => `<button class="btn${b.primary?' btn-primary':''}" data-i="${i}">${esc(b.label)}</button>`).join('')}</div>
      </div>
    </div>`;
  document.getElementById('alert-overlay')?.addEventListener('click', e => {
    if (e.target.id === 'alert-overlay') root.innerHTML = '';
  });
  root.querySelectorAll('.btn[data-i]').forEach(btn => {
    btn.addEventListener('click', () => {
      const b = btns[Number(btn.dataset.i)];
      root.innerHTML = '';
      if (b.fn) b.fn();
    });
  });
}

function setupGlobalListeners() {
  document.getElementById('qa-open')?.addEventListener('click', openDatabase);
  document.getElementById('qa-new')?.addEventListener('click', createNewDatabase);

  // Documented shortcuts: Ctrl/Cmd+S save, Ctrl/Cmd+O open, Ctrl/Cmd+N new.
  document.addEventListener('keydown', e => {
    const mod = e.ctrlKey || e.metaKey;
    if (!mod) return;
    const key = e.key.toLowerCase();
    if (key === 's') {
      e.preventDefault();
      if (db) saveToDisk().then(() => toast('Database saved'));
    } else if (key === 'o') {
      e.preventDefault();
      openDatabase();
    } else if (key === 'n') {
      e.preventDefault();
      createNewDatabase();
    }
  });
}