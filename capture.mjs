import { chromium } from 'playwright';
import { expect } from 'playwright/test';

async function runScript() {
  const expected_version = process.argv[2];
  const expected_env = process.argv[3];
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto('http://localhost:8086');
  await page.waitForTimeout(5000);
  await expect(page.getByText('R is free software and comes with ABSOLUTELY NO WARRANTY.')).toBeVisible();
  await expect(page.getByText('Active conda environment: anaconda50_r')).toBeVisible();
  await page.locator('*:focus').pressSequentially('RStudio.Version()$version\nR.home()\n');
  await expect(page.getByText(expected_version).last()).toBeVisible();
  await expect(page.getByText(expected_env).last()).toBeVisible();
  await page.screenshot({path: './test_screenshot.png', scale: 'css', type: 'png'});
  await browser.close();
}

runScript();