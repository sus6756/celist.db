celist.db — a friendly SQLite database app for the rest of us. (Windows Edition)

-------------------------------------------------
INSTALL
-------------------------------------------------

1. Unzip celist-db-windows.zip.
2. Double-click celist-db-windows-portable-1.0.0.exe.
   celist.db runs directly — no install needed.

OR run the installer: celist-db-windows-setup-1.0.0.exe
(installs celist.db into Program Files with a Start Menu entry)

First launch note:
Because celist.db is a direct download, Windows SmartScreen may
show: "Windows protected your PC". This is normal for newly
published apps that haven't yet built a reputation. To open:
   - Click "More info"
   - Click "Run anyway"
You only need to do this once.

-------------------------------------------------
GETTING STARTED
-------------------------------------------------

On the welcome screen choose "Create Sample Database" to load
a ready-made shop database (customers, orders, products) and
explore. Then:

   Tables    — click a table in the sidebar to browse its data,
               click a cell to edit, use the Home ribbon to add,
               duplicate, or delete records.

   New Table — design a table visually (no SQL needed); we write
               the SQL for you.

   SQL Query — write raw SQL in the built-in editor and see results
               in a grid. Use Ctrl+Return to run a query.

Keyboard: Ctrl+Return run query, Ctrl+S save, Ctrl+O open,
Ctrl+N new database.

-------------------------------------------------
REQUIREMENTS
-------------------------------------------------

   Windows 10 or 11, 64-bit.

-------------------------------------------------
BUILDING THE EXE (for developers)
-------------------------------------------------

Do this on a Windows PC (or a Mac with Wine installed):

   npm install
   npm run dist

Output goes to dist\ and contains:
   celist-db-windows-portable-1.0.0.exe  (runs anywhere, no install)
   celist-db-windows-setup-1.0.0.exe     (installer)

-------------------------------------------------
BUGS & FEEDBACK
-------------------------------------------------

Found a bug or want a feature? Open an issue at
https://github.com/sus6756/celist.db/issues — feedback is welcome.
