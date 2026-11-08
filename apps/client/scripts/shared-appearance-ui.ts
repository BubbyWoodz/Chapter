// Actual original Preact hook in a synthetic DOM. No browser/visual or relay claim.
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { h,render } from 'preact';
import { act } from 'preact/test-utils';
import { useTheme,type ThemeControls } from '../src/hooks/useTheme';
import type { SharedAppearance } from '../src/appearance/shared';
const dom=new JSDOM('<!doctype html><html><body><div id="app"></div></body></html>',{url:'https://public.chapter.invalid'});
Object.assign(globalThis,{window:dom.window,document:dom.window.document,localStorage:dom.window.localStorage,getComputedStyle:dom.window.getComputedStyle.bind(dom.window)});
Object.defineProperty(dom.window,'matchMedia',{value:()=>({matches:false,addEventListener(){},removeEventListener(){}})});
const root=document.getElementById('app')!,box:{controls?:ThemeControls}={};
const calls:SharedAppearance[]=[];
let shared={value:{v:1,mode:'dark',palette:'twilight',skin:'modern'} as unknown,ready:true,save:async(p:SharedAppearance)=>{calls.push(p)}};
function Probe({options}:{options:typeof shared}) {box.controls=useTheme(options);return h('div',{},box.controls.syncMessage)}
async function paint() {await act(async()=>{render(h(Probe,{options:{...shared}}),root)})}
await paint();assert(box.controls);assert.equal(box.controls.skin,'modern');assert.equal(box.controls.mode,'dark');assert.equal(calls.length,0,'Remote preferences must not echo upload');
await act(async()=>{box.controls!.setSkin('forest');box.controls!.setPalette('plum')});
assert.equal(calls.length,2);assert.deepEqual(calls[0],{v:1,mode:'dark',palette:'moss',skin:'forest'});assert.deepEqual(calls[1],{v:1,mode:'dark',palette:'plum',skin:'forest'});
shared={...shared,value:{v:1,mode:'light',palette:'sea',skin:'terminal'}};await paint();
assert.equal(box.controls.mode,'light');assert.equal(box.controls.skin,'terminal');assert.equal(calls.length,2);
shared={...shared,ready:false};await paint();await act(async()=>{box.controls!.setMode('dark')});
assert.equal(calls.length,2);assert(box.controls.syncMessage.includes('Local preview only'));
shared={...shared,ready:true,save:async()=>{throw new Error('Public injected storage failure')}};await paint();
await act(async()=>{box.controls!.setPalette('rose')});assert(box.controls.syncMessage.includes('could not be saved'));
assert.equal(localStorage.getItem('mneme.theme.palette'),'rose','A failed durable save is clearly labeled a retained local preview');
render(null,root);dom.window.close();
console.log('PASS actual Preact appearance hook: remote application without echo, atomic rapid skin/accent actions, offline preview gating and explicit durable-failure status.');
