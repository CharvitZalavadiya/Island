ISLAND - READ ME FIRST

1. Drag Island onto the Applications folder, then open it from Applications.

2. The first time, macOS may say it "cannot verify" Island, or that it "can't be opened".
   That is only because Island is not signed with a paid Apple developer account. It is
   free and its code is public: https://github.com/CharvitZalavadiya/Island

   To open it anyway (do this once):
     - Open System Settings > Privacy & Security, scroll down to the message about
       "Island" and press "Open Anyway", then confirm.
   or, in Terminal:
         xattr -dr com.apple.quarantine /Applications/Island.app

3. Island has no Dock icon. Look at the top middle of your screen: on a Mac with a notch
   it lives in the notch; on any other Mac it shows a small black notch of its own.
   Move the pointer there (or click it) to open it. To quit, open it and use the gear
   icon > Quit Island.

Needs macOS 14.2 (Sonoma) or later.
