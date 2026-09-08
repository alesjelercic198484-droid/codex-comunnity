/* OQV2 static analyzer: cross-file symbol + event-name consistency */
const fs=require('fs'),path=require('path'),luaparse=require('luaparse');
const root='oqv2_quests';
let files=[];(function w(d){for(const f of fs.readdirSync(d)){const p=path.join(d,f);
 fs.statSync(p).isDirectory()?w(p):f.endsWith('.lua')&&files.push(p);}})(root);

const defined=new Set(), used=new Map();
const netRegistered=new Set(), netTriggered=new Map();
const cbRegistered=new Set(), cbAwaited=new Map();
const nuiRegistered=new Set();
const problems=[];

function memberPath(node){
  if(node.type==='Identifier')return node.name;
  if(node.type==='MemberExpression'){const b=memberPath(node.base);return b?b+'.'+node.identifier.name:null;}
  return null;
}
function strArg(a){return a&&a.type==='StringLiteral'?(a.value!==undefined&&a.value!==null?a.value:a.raw.slice(1,-1)):null;}

for(const f of files){
  const ast=luaparse.parse(fs.readFileSync(f,'utf8'),{luaVersion:'5.3',locations:true});
  (function walk(n,parent){
    if(!n||typeof n!=='object')return;
    if(Array.isArray(n))return n.forEach(x=>walk(x,parent));
    if(n.type==='AssignmentStatement'){
      n.variables.forEach(v=>{const p=memberPath(v);if(p&&p.startsWith('OQ'))defined.add(p);});
    }
    if(n.type==='FunctionDeclaration'&&n.identifier){
      const p=memberPath(n.identifier);if(p&&p.startsWith('OQ'))defined.add(p);
    }
    if(n.type==='TableKeyString'&&parent&&parent.__oqPrefix){
      defined.add(parent.__oqPrefix+'.'+n.key.name);
    }
    if(n.type==='MemberExpression'){
      const p=memberPath(n);
      if(p&&p.startsWith('OQ.')){ if(!used.has(p))used.set(p,[]); used.get(p).push(f+':'+n.loc.start.line); }
    }
    if(n.type==='CallExpression'||n.type==='StringCallExpression'){
      const callee=memberPath(n.base)||'';
      const args=n.arguments||(n.argument?[n.argument]:[]);
      const s0=strArg(args[0]);
      if(callee==='RegisterNetEvent'&&s0)netRegistered.add(s0);
      if((callee==='TriggerClientEvent'||callee==='TriggerServerEvent'||callee==='TriggerEvent'||callee==='TriggerLatentClientEvent')&&s0){
        if(!netTriggered.has(s0))netTriggered.set(s0,[]);netTriggered.get(s0).push({f,line:n.loc.start.line,callee});
      }
      if(callee==='AddEventHandler'&&s0)netRegistered.add(s0);
      if(callee==='lib.callback.register'&&s0)cbRegistered.add(s0);
      if(callee==='lib.callback.await'&&s0){if(!cbAwaited.has(s0))cbAwaited.set(s0,[]);cbAwaited.get(s0).push(f+':'+n.loc.start.line);}
      if(callee==='RegisterNUICallback'&&s0)nuiRegistered.add(s0);
    }
    for(const k in n){ if(k==='loc')continue; const v=n[k];
      if(v&&typeof v==='object'){ if(n.type==='AssignmentStatement'&&k==='init'){
          const p=memberPath(n.variables[0]); if(p&&p.startsWith('OQ')&&v[0]&&v[0].type==='TableConstructorExpression'){v[0].__oqPrefix=p;}
        } walk(v,n); }
    }
  })(ast,null);
}
// OQ root + known dynamic
['OQ','OQ.Registry.missions','OQ.Registry.locations','OQ.Registry.npcs','OQ.Schema','OQ.DB','OQ.Server','OQ.Client','OQ.Missions','OQ.Npcs','OQ.Admin','OQ.Progression','OQ.State','OQ.locale','OQ.branding','OQ.resource','OQ.version','OQ.isServer'].forEach(x=>defined.add(x));

console.log('=== OQ.* symbols used but never defined ===');
let bad=0;
for(const [p,locs] of [...used].sort()){
  if(!defined.has(p)){
    // allow deep field access on defined table (e.g. OQ.State.world.locations)
    const parts=p.split('.'); let ok=false;
    for(let i=parts.length-1;i>=2;i--){ if(defined.has(parts.slice(0,i).join('.'))){ok=true;break;} }
    if(!ok){ bad++; console.log('  MISSING '+p+'   ('+locs[0]+', '+locs.length+' use(s))'); }
  }
}
if(!bad)console.log('  none');

console.log('\n=== net events triggered to clients/server without a handler ===');
let be=0;
for(const [name,list] of [...netTriggered].sort()){
  if(name.startsWith('oqv2:')&&!netRegistered.has(name)){be++;console.log('  MISSING handler for "'+name+'"  '+list.map(l=>l.f+':'+l.line).join(', '));}
}
if(!be)console.log('  none');

console.log('\n=== ox_lib callbacks awaited without a register ===');
let bc=0;
for(const [name,locs] of [...cbAwaited].sort()){
  if(!cbRegistered.has(name)){bc++;console.log('  MISSING register for "'+name+'"  '+locs.join(', '));}
}
if(!bc)console.log('  none');

console.log('\n=== registered but never awaited callbacks ===');
for(const n of [...cbRegistered].sort())if(!cbAwaited.has(n))console.log('  unused: '+n);

console.log('\nNUI callbacks registered: '+[...nuiRegistered].sort().join(', '));
process.exit((bad+be+bc)?1:0);
