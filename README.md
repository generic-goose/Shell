<h1>Shell Console</h1>
Shell is a small project focused on command-centered functions and easy customization and additions. 
<h3>Addons</h2>
Addons can be loadstring or files, uploaded directly to the Shell interface or via the import function and a github repo. Almost every part of Shell can be customized or changed with Themes and Addons, making it easy to make new tools and functions.
<h3>Themes</h2>
Themes can be loaded via Shell/Assets/Themes, although the initial launch of Shell will also add all of the default Shell themes to your themes folder.
<h3>Built-In</h2>
Shell will try to import the Functions folder in this repository, with additional common-use commands and developer tools such as Cobalt and DEX.
<h1>Installation</h1>
<h3>Automatic</h2>
You can automatically install Shell by running <code>loadstring(game:HttpGet("https://raw.githubusercontent.com/generic-goose/Shell/refs/heads/main/Core/compiler.lua"))()</code>.
<h3>Manual</h2>
You can manually install Shell by downloading the folders above, and placing them inside of your workspace, then run <code>loadstring(readfile("Shell/Core/compiler.lua"))</code>.
<h3>Requirements</h3>
- Must have HTTP services for github loading.
