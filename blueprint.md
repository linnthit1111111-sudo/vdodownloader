
# NMS Downloader - Blueprint

## Overview

This document outlines the plan and features for the `nms-downloader` application. The goal is to create a versatile Flutter application that allows users to browse, download, and manage videos from various online platforms.

**Disclaimer:** Downloading content from platforms may be against their Terms of Service. This is for educational purposes only.

## Current Plan: Unified Downloads Tab

The UI will be streamlined by merging the "Downloads" and "Video List" tabs into a single, comprehensive "Downloads" tab.

1.  **Two-Tab Layout:** The bottom navigation will be simplified to two primary tabs: **Home** (for browsing) and **Downloads** (for managing all downloads).
2.  **Combined View:** The new **Downloads** tab will display:
    *   The status and progress of any **currently active download** at the top.
    *   A **list of all completed videos** below the active download section.
3.  **State Management:** The logic for displaying the current download and the list of saved files will be combined into a single `DownloadsPage` widget.

### Implemented Features (v4.0)

-   **Multi-Video Selection:** When a page has multiple videos, a dialog with a `ListView` allows the user to select which video to download.
-   **Enhanced Download UX:** The download button turns red when a video is detected, and a confirmation dialog appears on tap.
-   **Downloader Service:** A modular service (`DownloaderService`) is in place to handle downloads.
