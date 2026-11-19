import {test} from 'node:test';
import assert from 'node:assert/strict';
import {BilibiliLogin} from '../src/bilibili.mjs';

test('failed replacement login restores the previous usable account for existing tasks', async()=>{
 const login=new BilibiliLogin({});
 const cookies=[{name:'SESSDATA',value:'fictional-old'}];
 let restored;
 login.context={storageState:async()=>({cookies}), clearCookies:async()=>{}, addCookies:async value=>{restored=value;}};
 login.status={state:'ready',account:{id:'100',name:'Test'}};
 login.verify=async()=>{login.status={state:'error'};throw Error('B 站 validation rejected');};
 await assert.rejects(login.importPhone('SESSDATA=fictional-new; DedeUserID=200'));
 assert.deepEqual(restored,cookies);
 assert.equal(login.status.state,'ready');
 assert.equal(login.status.account.id,'100');
});
