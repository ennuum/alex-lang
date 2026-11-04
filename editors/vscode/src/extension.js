// Extension VS Code pour ALEX : IntelliSense par le serveur de langage `alexc lsp` (LSP standard), débogage par
// l'adaptateur DAP src/dap.js (au-dessus de `alexc debug --protocol 2`), commandes d'exécution et de tests.
'use strict';

const vscode = require('vscode');
const path = require('path');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

let client = null;

function alexPath() {
    return vscode.workspace.getConfiguration('alex').get('path') || 'alex';
}

function terminal(args) {
    const t = vscode.window.createTerminal({ name: 'ALEX' });
    t.show();
    t.sendText([alexPath()].concat(args).map((a) => (/\s/.test(a) ? '"' + a + '"' : a)).join(' '));
}

function activate(context) {
    const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
    const serverOptions = {
        command: alexPath(),
        args: ['lsp'].concat(folder ? [folder.uri.fsPath] : []),
        transport: TransportKind.stdio,
    };
    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'alex' }],
        synchronize: { fileEvents: vscode.workspace.createFileSystemWatcher('**/*.al') },
    };
    client = new LanguageClient('alex', 'ALEX (alexc lsp)', serverOptions, clientOptions);
    client.start();

    // débogueur : l'adaptateur DAP est un script Node fourni avec l'extension
    context.subscriptions.push(vscode.debug.registerDebugAdapterDescriptorFactory('alex', {
        createDebugAdapterDescriptor() {
            return new vscode.DebugAdapterExecutable(process.execPath, [path.join(context.extensionPath, 'src', 'dap.js')], {
                env: Object.assign({}, process.env, { ALEX_PATH: alexPath() }),
            });
        },
    }));
    context.subscriptions.push(vscode.debug.registerDebugConfigurationProvider('alex', {
        resolveDebugConfiguration(f, config) {
            if (!config.type) {
                const ed = vscode.window.activeTextEditor;
                if (!ed || ed.document.languageId !== 'alex') return undefined;
                config.type = 'alex';
                config.request = 'launch';
                config.name = 'Déboguer le fichier ALEX';
                config.program = ed.document.fileName;
            }
            if (!config.alexPath) config.alexPath = alexPath();
            if (!config.cwd && f) config.cwd = f.uri.fsPath;
            return config;
        },
    }));

    context.subscriptions.push(vscode.commands.registerCommand('alex.run', () => {
        const ed = vscode.window.activeTextEditor;
        if (ed) ed.document.save().then(() => terminal(['run', ed.document.fileName]));
    }));
    context.subscriptions.push(vscode.commands.registerCommand('alex.test', () => terminal(['test'])));
    // ALEX Studio est une application séparée (alex-studio, installée à part) : lancée sans terminal.
    context.subscriptions.push(vscode.commands.registerCommand('alex.studio', () => {
        const studio = vscode.workspace.getConfiguration('alex').get('studioPath') || 'alex-studio';
        const p = require('child_process').spawn(studio, [folder ? folder.uri.fsPath : '.'], { detached: true, stdio: 'ignore' });
        p.on('error', () => vscode.window.showErrorMessage('ALEX Studio introuvable (' + studio + ') : installez-le ou réglez alex.studioPath.'));
        p.unref();
    }));

    // tâches : alexc run / test / check / build / fmt / doc
    context.subscriptions.push(vscode.tasks.registerTaskProvider('alex', {
        provideTasks() {
            const mk = (cmd, args, group) => {
                const t = new vscode.Task({ type: 'alex', command: cmd }, vscode.TaskScope.Workspace, 'alex ' + cmd, 'alex', new vscode.ProcessExecution(alexPath(), args));
                if (group) t.group = group;
                return t;
            };
            return [
                mk('test', ['test'], vscode.TaskGroup.Test),
                mk('build', ['build', '--standalone', 'main.al', '-o', 'dist/app'], vscode.TaskGroup.Build),
                mk('fmt', ['fmt', '.']),
                mk('doc', ['doc', '--html', 'docs/api', '.']),
            ];
        },
        resolveTask(t) { return t; },
    }));
}

function deactivate() {
    return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };
