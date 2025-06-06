#!/usr/bin/env python3
"""
Auto-generated directory structure validation script for Pi-Swarm
Generated: 2025-06-07T00:24:59.151487
"""

import sys
from pathlib import Path

# Add lib/python to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "lib" / "python"))

from directory_manager import DirectoryManager


def main():
    """Main validation function."""
    project_root = Path(__file__).parent.parent.parent
    manager = DirectoryManager(str(project_root))
    
    print("🔍 Validating Pi-Swarm directory structure...")
    statuses = manager.validate_directory_structure()
    
    # Summary
    total = len(statuses)
    existing = sum(1 for s in statuses if s.exists)
    missing = total - existing
    issues = sum(len(s.issues) for s in statuses)
    
    print(f"\n📊 Summary:")
    print(f"  Total directories: {total}")
    print(f"  Existing: {existing}")
    print(f"  Missing: {missing}")
    print(f"  Issues: {issues}")
    
    if issues == 0:
        print("  ✅ All directories are correctly configured!")
        return 0
    else:
        print("  ❌ Issues found:")
        for status in statuses:
            if status.issues:
                print(f"    {status.path}: {', '.join(status.issues)}")
        return 1


if __name__ == '__main__':
    exit(main())
