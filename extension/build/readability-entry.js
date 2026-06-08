// Bundled into a global so it can be injected into a page via chrome.scripting.executeScript.
import { Readability, isProbablyReaderable } from '@mozilla/readability';
window.__BeamhopReadability = { Readability, isProbablyReaderable };
