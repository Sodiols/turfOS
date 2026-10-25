import {chromium} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import assert from 'node:assert/strict';
import {mkdir} from 'node:fs/promises';
await mkdir('.local/screens',{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
try{
for(const width of [1440,390]){
 const context=await browser.newContext({viewport:{width,height:900}});
 const page=await context.newPage();
 for(const route of ['/','/features','/pricing','/help','/contact','/login','/signup','/legal/privacy']){
  const response=await page.goto(`http://127.0.0.1:3200${route}`,{waitUntil:'domcontentloaded'});
  assert.equal(response.status(),200,route);
  assert.equal(await page.locator('h1').count(),1,`${route} has one h1`);
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth+2);
  assert.equal(overflow,false,`${route} horizontal overflow at ${width}`);
  if(route==='/'){
   await page.screenshot({path:`.local/screens/home-${width}.png`,fullPage:true});
   const axe=await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa']).analyze();
   assert.equal(axe.violations.length,0,JSON.stringify(axe.violations.map(v=>({id:v.id,nodes:v.nodes.map(n=>({target:n.target,summary:n.failureSummary}))}))));
  }
 }
 await context.close();
 console.log(`PASS: public routes, no horizontal overflow, home accessibility at ${width}px`);
}
}finally{await browser.close()}
