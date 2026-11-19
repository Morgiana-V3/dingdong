import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { SubscriptionRegistry, Subscriptions } from '../src/subscriptions.mjs';

function fixture() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dingdong-subscriptions-'));
  const registry = new SubscriptionRegistry();
  registry.register({ id: 'test-feed', name: 'Test feed', accountId: 'test-account', accountName: 'Test account', fields: [{key:'limit',type:'number',min:1,max:20,default:5,label:'Limit'}], collect: async () => [{id:'video-1',title:'A < B',url:'https://www.bilibili.com/video/BVtest',author:'Test'}] });
  let account = {state:'idle'};
  let now = 1000;
  const sent = [];
  const options = { directory, registry, account: () => account, now: () => now, publish: async payload => {sent.push(payload);} };
  const engine = new Subscriptions(options);
  return { engine, options, sent, setAccount: value => {account=value;}, setNow: value=>{now=value;}, clean:()=>fs.rmSync(directory,{recursive:true,force:true}) };
}
const save = (revision=0, extra={}) => ({action:'save',revision,name:'Test subscription',pluginId:'test-feed',enabled:true,minutes:5,config:{limit:5},...extra});

test('foreign posts translate automatically with the task model or the server fallback', async () => {
  const f = fixture();
  try {
    const calls = [];
    f.engine.runtime = {
      providers: [{ id: 'first' }, { id: 'assigned' }],
      services: {
        generate: async (id, prompt) => {
          calls.push(id);
          return JSON.stringify(JSON.parse(prompt.split('\n').at(-1)).map(() => '正在发布新版'));
        },
      },
    };
    const html = '<html><head></head><body><main><article class="post"><div class="post-content"><h2>Release notes</h2><p>A new version is rolling out.</p></div></article></main></body></html>';
    const message = { title: 'Test task', short: '' };
    const assigned = await f.engine.preview(html, message, { name: 'Test task', providerId: 'assigned', translate: false });
    const fallback = await f.engine.preview(html, message, { name: 'Test task' });
    assert.equal(assigned.title, '正在发布新版');
    assert.equal(fallback.title, '正在发布新版');
    assert.deepEqual(calls, ['assigned', 'first']);
  } finally {
    f.clean();
  }
});

test('installed plugins drive tasks, account requirements, login gating and scheduled delivery', async () => {
 const f=fixture(); try {
  assert.equal(f.engine.snapshot().plugins.length,1);
  assert.deepEqual(f.engine.requiredAccounts(),[]);
  let s=await f.engine.command(save());
  assert.equal(s.tasks[0].state,'needs_login');
  assert.equal(s.accounts[0].tasks[0].name,'Test subscription');
  await f.engine.tick(); assert.equal(f.sent.length,0);
  f.setAccount({state:'ready',account:{name:'Test'}});
  await f.engine.tick(); assert.equal(f.sent.length,1);
  assert.match(f.sent[0].content,/A &lt; B/);
  assert.match(f.sent[0].content, /<article class="post bilibili">/);
  assert.match(f.sent[0].content, /@media \(prefers-color-scheme: dark\)/);
  assert.match(f.sent[0].content, /href="https:\/\/www\.bilibili\.com\/video\/BVtest"/);
  f.setNow(400000); await f.engine.tick(); assert.equal(f.sent.length,1);
  s=await f.engine.command({action:'toggle',revision:1,id:s.tasks[0].id,enabled:false});
  assert.deepEqual(s.accounts,[]);
  assert.equal(s.tasks[0].state,'paused');
  const restored=new Subscriptions(f.options); assert.equal(restored.snapshot().tasks.length,1);
  assert.deepEqual(restored.requiredAccounts(),[]);
 } finally {f.clean();}
});

test('lost send response persists identical outbox and retries after restart without duplicate publication',async()=>{
 const f=fixture();try {
  f.setAccount({state:'ready'});
  const s=await f.engine.command(save());
  const attempts=[];
  f.engine.publish=async payload=>{attempts.push(payload);throw Error('connection lost');};
  await assert.rejects(f.engine.command({action:'run',revision:1,id:s.tasks[0].id}));
  assert.equal(f.engine.snapshot().tasks[0].state,'error');
  assert.equal(f.engine.snapshot().tasks[0].pending,undefined);
  const restored=new Subscriptions({...f.options,publish:async payload=>{attempts.push(payload);}});
  await restored.command({action:'run',revision:1,id:s.tasks[0].id});
  assert.deepEqual(attempts[0],attempts[1]);
  assert.equal(restored.state.tasks[0].pending,undefined);
  assert.deepEqual(restored.state.tasks[0].seen,['video-1']);
 }finally{f.clean();}
});

test('stale edits and unknown plugins are rejected; tasks requiring the same account share one login',async()=>{
 const f=fixture();try{
  const first=await f.engine.command(save());
  await assert.rejects(f.engine.command(save(0)),error=>error.status===409);
  await assert.rejects(f.engine.command(save(1,{pluginId:'uninstalled'})));
  await assert.rejects(f.engine.command(save(1,{minutes:0})));
  const second=await f.engine.command(save(1,{name:'Second task'}));
  assert.equal(second.accounts.length,1); assert.equal(second.accounts[0].tasks.length,2);
  await f.engine.command({action:'delete',revision:2,id:first.tasks[0].id});
  assert.equal(f.engine.requiredAccounts()[0].tasks.length,1);
  f.options.registry.plugins.clear();
  assert.equal(f.engine.snapshot().tasks[0].state,'unavailable');
  await f.engine.tick(); assert.equal(f.sent.length,0);
 }finally{f.clean();}
});

test('legacy tasks edited with Studio schedules retain manual and daily scheduling semantics', async () => {
 const f=fixture();try {
  f.setAccount({state:'ready'});
  const result=await f.engine.command(save(0,{schedule:{type:'manual'}}));
  await f.engine.tick(); assert.equal(f.sent.length,0);
  await f.engine.command({action:'run',id:result.tasks[0].id,revision:1});
  assert.equal(f.engine.state.tasks[0].nextRunAt,null);
  await f.engine.command(save(1,{id:result.tasks[0].id,schedule:{type:'daily',times:['09:00']}}));
  assert.ok(f.engine.state.tasks[0].nextRunAt>1000);
 }finally{f.clean();}
});
