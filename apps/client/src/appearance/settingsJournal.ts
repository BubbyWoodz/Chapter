// Serial, durable settings/outbox/recovery state over ORIGINAL v1 seals/record codecs.
import { sealAiSettings,openAiSettings,AiSettingsDecryptionError,type SealedAiSettings } from '../ai/settings';
import { defaultAiSettings,type AiSettings } from '../ai/types';
import type { AiSettingsRecord } from '../sync/engine';
import { newRecordId } from '../sync/ids';
export interface SettingsDisk { load():Promise<SealedAiSettings|null>;store(value:SealedAiSettings,expected?:SealedAiSettings|null):Promise<void> }
export interface SettingsState { current:AiSettingsRecord|null; recovered:AiSettingsRecord[]; dirty:boolean }
const canonical=(value:unknown):string=>{
 if(value===null||typeof value!=='object')return JSON.stringify(value)??'null';
 if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
 const object=value as Record<string,unknown>;
 return '{'+Object.keys(object).filter(k=>object[k]!==undefined).sort().map(k=>JSON.stringify(k)+':'+canonical(object[k])).join(',')+'}';
};
const same=(a:AiSettingsRecord,b:AiSettingsRecord)=>a.recordId===b.recordId&&a.updatedAt===b.updatedAt&&!!a.deleted===!!b.deleted&&canonical(a.settings)===canonical(b.settings);
function validate(row:AiSettingsRecord):void {if(!row.recordId||!Number.isSafeInteger(row.updatedAt)||row.updatedAt<0)throw new Error('Invalid settings clock/identity');if(row.settings&&row.settings.v!==1)throw new Error('Unsupported settings version');}
export class SettingsJournal {
 private tail:Promise<unknown>=Promise.resolve();private active=true;private ready=false;private paused=false;private saved:SealedAiSettings|null=null;
 private state:SettingsState={current:null,recovered:[],dirty:false};
 constructor(private key:Uint8Array,private disk:SettingsDisk,private alive:()=>boolean,private publish:(state:SettingsState)=>void){}
 close():void {this.active=false;this.state={current:null,recovered:[],dirty:false};this.key=new Uint8Array();}
 drain():Promise<unknown> {return this.tail.catch(()=>undefined)}
 get isClosed():boolean{return !this.active}
 pause():void {this.paused=true}
 resume():void {this.paused=false}
 snapshot():SettingsState {return structuredClone(this.state)}
 restore(state:SettingsState):Promise<void>{return this.enqueue(async()=>{await this.commit(state);this.ready=true})}
 private check():void {if(!this.active||this.paused||!this.alive())throw new Error('Vault changed or locked');}
 private enqueue<T>(task:()=>Promise<T>):Promise<T> {const result=this.tail.catch(()=>undefined).then(async()=>{this.check();return task()});this.tail=result;return result;}
 private open(seal:SealedAiSettings):AiSettingsRecord {
   const settings=openAiSettings(this.key,seal),meta=seal.sync;
   const row:AiSettingsRecord={recordId:meta?.recordId??newRecordId(),updatedAt:meta?.updatedAt??Date.now(),settings:meta?.deleted?null:settings,...(meta?.deleted?{deleted:true}:{})};validate(row);return row;
 }
 private seal(row:AiSettingsRecord,dirty:boolean):SealedAiSettings {return sealAiSettings(this.key,row.settings??defaultAiSettings(),{recordId:row.recordId,updatedAt:row.updatedAt,dirty,...(row.deleted?{deleted:true}:{})})}
 private async commit(next:SettingsState):Promise<void> {
   this.check();if(next.current) {const seal=this.seal(next.current,next.dirty);seal.recovered=next.recovered.map(row=>this.seal(row,false));await this.disk.store(seal,this.saved);this.saved=seal}
   this.check();this.state=next;this.publish(next);
 }
 load():Promise<void> {return this.enqueue(async()=>{
   // A failed explicit reload must not leave an old state writable over new bytes.
   this.ready=false;
   const seal=await this.disk.load();this.check();this.saved=seal;
   if(!seal){this.ready=true;this.publish(this.state);return}
   let current:AiSettingsRecord;
   try {current=this.open(seal)}catch(error){if(seal.legacy&&error instanceof AiSettingsDecryptionError){this.saved=null;this.ready=true;this.publish(this.state);return}throw error}
   const recovered=(seal.recovered??[]).map(s=>this.open(s));
   if(this.state.dirty&&this.state.current&&!same(this.state.current,current)&&!recovered.some(r=>same(r,this.state.current!))){if(recovered.length>=256)throw new Error('Settings recovery is full');recovered.push(this.state.current);}
   const next={current,recovered,dirty:seal.sync?.dirty??true};
   // Successful legacy migration copies to the dedicated slot, never erases it.
   const changed=this.state.dirty&&this.state.current&&!same(this.state.current,current);
   if(seal.legacy||!seal.sync?.recordId||changed)await this.commit(next);
   else {this.state=next;this.publish(next)}
   this.ready=true;
 })}
 edit(change:(current:AiSettings|null)=>AiSettings|null,now=Date.now(),archive=false):Promise<void> {return this.enqueue(async()=>{
   if(!this.ready)throw new Error('Saved settings have not finished loading');
   const clock=Math.max(now,(this.state.current?.updatedAt??0)+1);
   if(!Number.isSafeInteger(clock)||clock<0)throw new Error('Invalid settings clock');
   const settings=change(this.state.current?.settings??null);
   const current:AiSettingsRecord={recordId:this.state.current?.recordId??newRecordId(),updatedAt:clock,settings,...(settings===null?{deleted:true}:{})};
   const recovered=[...this.state.recovered];
   if(archive&&this.state.current&&!recovered.some(row=>same(row,this.state.current!))) {
     if(recovered.length>=256)throw new Error('Settings recovery is full');recovered.push(this.state.current);
   }
   await this.commit({...this.state,current,recovered,dirty:true});
 })}
 receive(rows:AiSettingsRecord[]):Promise<void> {return this.enqueue(async()=>{
   if(!this.ready)throw new Error('Saved settings have not finished loading');
   let next:SettingsState={...this.state,recovered:[...this.state.recovered]};
   const recover=(row:AiSettingsRecord)=>{if(!next.recovered.some(r=>same(r,row))){if(next.recovered.length>=256)throw new Error('Settings recovery is full; retained versions must be reviewed before syncing');next.recovered.push(row)}};
   // Deterministic across pages/devices: highest clock, then smallest wire ID.
   for(const remote of [...rows].sort((a,b)=>a.updatedAt-b.updatedAt||b.recordId.localeCompare(a.recordId))) {
     validate(remote);const local=next.current;
     if(!local){next={...next,current:remote,dirty:false};continue}
     const id=local.recordId<remote.recordId?local.recordId:remote.recordId;
     const contentSame=!!local.deleted===!!remote.deleted&&canonical(local.settings)===canonical(remote.settings);
     const remoteWins=remote.updatedAt>local.updatedAt || (remote.updatedAt===local.updatedAt && remote.recordId<=local.recordId);
     if(remoteWins) {
       if(!contentSame&&(next.dirty||remote.updatedAt===local.updatedAt))recover(local);
       next={...next,current:{...remote,recordId:id},dirty:false};
     } else {
       if(!contentSame&&remote.updatedAt===local.updatedAt)recover(remote);
       next={...next,current:{...local,recordId:id}};
     }
   }
   await this.commit(next);
 })}
 acknowledge(sent:AiSettingsRecord):Promise<void> {return this.enqueue(async()=>{
   if(!this.ready)throw new Error('Saved settings have not finished loading');
   if(this.state.current&&same(this.state.current,sent)&&this.state.dirty)await this.commit({...this.state,dirty:false});
 })}
}
