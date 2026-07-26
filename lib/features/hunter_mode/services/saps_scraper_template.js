/**
 * SAPS License & Competency Application Status Scraper
 * 
 * Apify Actor template for automated tracking of SAPS firearm license
 * and competency certificate application statuses.
 * 
 * Target Portal: South African Police Service (SAPS) Online Status Check
 * Input: ID Number, Reference Number
 * Output: Current application status stage
 * 
 * @version 1.0.0
 * @requires @apify/actor-puppeteer
 */

const Apify = require('@apify/actor-puppeteer');

// SAPS Portal base URL for application status tracking
const SAPS_TRACKING_URL = 'https://www.saps.org.za/services/firearms-licensing/status-check';

/**
 * Main actor execution function
 */
Apify.main(async () => {
    // Initialize Puppeteer with headless browser
    const proxyConfiguration = await Apify.createProxyConfiguration({
        groups: ['RESIDENTIAL'],
        countryCode: 'ZA',
    });

    // Launch Puppeteer with optimized settings for SAPS portal
    const browser = await Apify.launchPuppeteer({
        proxyConfiguration,
        useChrome: true,
        stealth: true,
        launchOptions: {
            headless: true,
            args: [
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage',
                '--disable-accelerated-2d-canvas',
                '--no-sandbox',
            ],
        },
    });

    // Get input parameters
    const input = await Apify.getInput();
    const { idNumber, referenceNumber } = input;

    // Validate input parameters
    if (!idNumber || !referenceNumber) {
        throw new Error('Missing required input parameters: idNumber and referenceNumber');
    }

    // Initialize result object
    const result = {
        idNumber: idNumber,
        referenceNumber: referenceNumber,
        status: null,
        statusCode: null,
        lastChecked: new Date().toISOString(),
        rawResponse: null,
        success: false,
        error: null,
    };

    try {
        // Open new page and navigate to SAPS tracking portal
        const page = await browser.newPage();
        
        // Set viewport and user agent
        await page.setViewport({ width: 1280, height: 800 });
        await page.setExtraHTTPHeaders({
            'Accept-Language': 'en-ZA,en;q=0.9',
        });

        // Navigate to the SAPS status check page
        await page.goto(SAPS_TRACKING_URL, {
            waitUntil: 'networkidle2',
            timeout: 30000,
        });

        // Wait for page to stabilize
        await page.waitForTimeout(2000);

        // Check if page loaded successfully
        const pageTitle = await page.title();
        result.rawResponse = `Page loaded: ${pageTitle}`;

        // Locate ID Number input field
        const idInputSelector = await _findInputSelector(page, ['idNumber', 'id_number', 'saId', 'sa_id', 'txtIdNumber', 'ctl00$idNumber']);
        if (!idInputSelector) {
            throw new Error('ID Number input field not found');
        }

        // Locate Reference Number input field
        const refInputSelector = await _findInputSelector(page, ['reference', 'refNumber', 'reference_number', 'applicationRef', 'txtReference']);
        if (!refInputSelector) {
            throw new Error('Reference Number input field not found');
        }

        // Inject ID Number
        await page.waitForSelector(idInputSelector, { visible: true });
        await page.type(idInputSelector, idNumber, { delay: 50 });

        // Inject Reference Number
        await page.type(refInputSelector, referenceNumber, { delay: 50 });

        // Handle ASP.NET VIEWSTATE if present
        await _handleAspNetPostback(page);

        // Locate and click submit button
        const submitSelector = await _findSubmitSelector(page);
        if (!submitSelector) {
            throw new Error('Submit button not found');
        }

        // Click submit and wait for response
        await Promise.all([
            page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 30000 }),
            page.click(submitSelector),
        ]);

        // Handle any ASP.NET postback after submission
        await _handleAspNetPostback(page);

        // Wait for results panel to load
        await page.waitForTimeout(3000);

        // Parse status from result panel
        const statusData = await _parseStatusResponse(page);
        
        result.status = statusData.statusText;
        result.statusCode = statusData.statusCode;
        result.success = true;

        // Close page
        await page.close();

    } catch (error) {
        result.error = error.message;
        result.success = false;
    } finally {
        // Always close browser
        await browser.close();
    }

    // Output result as structured JSON
    await Apify.setOutputData(result);
    
    // Log result for debugging
    console.log('SAPS Scraper Result:', JSON.stringify(result, null, 2));
});

/**
 * Handle ASP.NET __VIEWSTATE modifications
 * SAPS portal uses classic ASP.NET with VIEWSTATE for form state
 */
async function _handleAspNetPostback(page) {
    try {
        // Check if __VIEWSTATE hidden field exists
        const viewStateExists = await page.$('input[name="__VIEWSTATE"]');
        if (viewStateExists) {
            // Wait for any async ASP.NET postback handlers
            await page.waitForFunction(() => {
                const btn = document.querySelector('input[type="submit"]');
                return !btn || !btn.disabled;
            }, { timeout: 5000 }).catch(() => {});
        }
    } catch (e) {
        // VIEWSTATE handling is optional - continue even if it fails
        console.log('VIEWSTATE handling skipped:', e.message);
    }
}

/**
 * Find input field selector using multiple possible identifiers
 */
async function _findInputSelector(page, possibleNames) {
    for (const name of possibleNames) {
        // Try various selector patterns
        const selectors = [
            `#${name}`,
            `[id*="${name}"]`,
            `[name="${name}"]`,
            `[name*="${name}"]`,
            `input[placeholder*="${name}"]`,
            `input[aria-label*="${name}"]`,
            `input[id$="${name}"]`,
        ];

        for (const selector of selectors) {
            try {
                const element = await page.$(selector);
                if (element) {
                    const isVisible = await element.isVisible();
                    if (isVisible) {
                        return selector;
                    }
                }
            } catch (e) {
                // Continue to next selector
            }
        }
    }
    return null;
}

/**
 * Find submit button selector
 */
async function _findSubmitSelector(page) {
    const submitSelectors = [
        'input[type="submit"]',
        'button[type="submit"]',
        'input[value*="Search"]',
        'input[value*="Check"]',
        'input[value*="Submit"]',
        'button:contains("Submit")',
        'button:contains("Check")',
        '[id*="btnSubmit"]',
        '[id*="btnCheck"]',
        '[id*="Submit"]',
    ];

    for (const selector of submitSelectors) {
        try {
            const element = await page.$(selector);
            if (element) {
                const isVisible = await element.isVisible();
                if (isVisible) {
                    return selector;
                }
            }
        } catch (e) {
            // Continue to next selector
        }
    }
    return null;
}

/**
 * Parse the status response from the result panel
 * Maps raw SAPS status text to standardized stages
 */
async function _parseStatusResponse(page) {
    const statusPatterns = [
        // Stage 0 - Submitted/DFO
        { pattern: /submitted|received at dfo|district firearms|application received/i, stage: 'Submitted' },
        // Stage 1 - Provincial Office
        { pattern: /provincial|province|provincial office|at provincial/i, stage: 'Provincial' },
        // Stage 2 - Central Firearms Registry (CFR)
        { pattern: /cfr|central firearms registry|at cfr|registry processing/i, stage: 'CFR' },
        // Stage 3 - Printed/Ready for Collection
        { pattern: /printed|ready for collection|completed|approved|licence printed/i, stage: 'Printed' },
        // Error states
        { pattern: /not found|no record|invalid|error|unable to locate/i, stage: 'Not Found' },
    ];

    // Try multiple methods to extract status text
    let statusText = null;

    // Method 1: Look for status result containers
    const statusSelectors = [
        '.status-result',
        '.result-status',
        '#status',
        '#result',
        '[class*="status"]',
        '[class*="result"]',
        'span[id*="status"]',
        'div[id*="status"]',
        'td[class*="status"]',
        'table[class*="result"]',
    ];

    for (const selector of statusSelectors) {
        try {
            const elements = await page.$$(selector);
            for (const el of elements) {
                const text = await el.innerText();
                if (text && text.trim().length > 0) {
                    statusText = text.trim();
                    break;
                }
            }
            if (statusText) break;
        } catch (e) {
            // Continue to next selector
        }
    }

    // Method 2: Get all page text and look for status keywords
    if (!statusText) {
        const bodyText = await page.evaluate(() => document.body.innerText);
        
        for (const { pattern, stage } of statusPatterns) {
            if (pattern.test(bodyText)) {
                statusText = stage;
                break;
            }
        }
    }

    // Method 3: Look for specific table cells with status data
    if (!statusText) {
        const cellText = await page.evaluate(() => {
            const cells = document.querySelectorAll('td, th');
            for (const cell of cells) {
                const text = cell.innerText.trim();
                if (text.length > 0 && text.length < 100) {
                    return text;
                }
            }
            return null;
        });
        if (cellText) {
            statusText = cellText;
        }
    }

    // Default status if nothing found
    if (!statusText) {
        statusText = 'Pending Review';
    }

    // Map status text to stage code
    let statusCode = 0;
    for (const { pattern, stage } of statusPatterns) {
        if (pattern.test(statusText)) {
            switch (stage) {
                case 'Submitted':
                    statusCode = 0;
                    break;
                case 'Provincial':
                    statusCode = 1;
                    break;
                case 'CFR':
                    statusCode = 2;
                    break;
                case 'Printed':
                    statusCode = 3;
                    break;
                case 'Not Found':
                    statusCode = -1;
                    break;
            }
            break;
        }
    }

    return {
        statusText: statusText,
        statusCode: statusCode,
    };
}
