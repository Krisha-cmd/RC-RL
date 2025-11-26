#!/usr/bin/env python3
"""
RL Agent Performance Comparison Tool

Analyzes and compares performance logs from RL-enabled vs RL-disabled runs.
Generates summary statistics and visualizations.

Usage:
    python analyze_rl_logs.py <rl_on_csv> <rl_off_csv>
    python analyze_rl_logs.py output/  # Analyzes all CSVs in directory
"""

import csv
import sys
import os
from pathlib import Path
from collections import defaultdict
import statistics

def load_log_csv(csv_path):
    """Load performance log CSV file."""
    entries = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            entry = {
                'entry': int(row['entry']),
                'rl_enabled': int(row.get('rl_enabled', 0)),
                'fifo1_load': int(row['fifo1_load']),
                'fifo2_load': int(row['fifo2_load']),
                'fifo3_load': int(row['fifo3_load']),
                'core0_div': int(row['core0_div']),
                'core1_div': int(row['core1_div']),
                'core2_div': int(row['core2_div']),
                'core3_div': int(row['core3_div']),
            }
            entries.append(entry)
    return entries


def analyze_logs(entries, label=""):
    """Calculate statistics for log entries."""
    if not entries:
        return None
    
    n = len(entries)
    
    # FIFO statistics
    fifo1_vals = [e['fifo1_load'] for e in entries]
    fifo2_vals = [e['fifo2_load'] for e in entries]
    fifo3_vals = [e['fifo3_load'] for e in entries]
    
    # Divider statistics
    div0_vals = [e['core0_div'] for e in entries]
    div1_vals = [e['core1_div'] for e in entries]
    div2_vals = [e['core2_div'] for e in entries]
    div3_vals = [e['core3_div'] for e in entries]
    
    # RL state
    rl_states = [e['rl_enabled'] for e in entries]
    
    stats = {
        'label': label,
        'count': n,
        'rl_enabled_pct': 100 * sum(rl_states) / n,
        
        # FIFO averages
        'fifo1_avg': statistics.mean(fifo1_vals),
        'fifo2_avg': statistics.mean(fifo2_vals),
        'fifo3_avg': statistics.mean(fifo3_vals),
        
        # FIFO max (indicates potential bottlenecks)
        'fifo1_max': max(fifo1_vals),
        'fifo2_max': max(fifo2_vals),
        'fifo3_max': max(fifo3_vals),
        
        # Divider averages
        'div0_avg': statistics.mean(div0_vals),
        'div1_avg': statistics.mean(div1_vals),
        'div2_avg': statistics.mean(div2_vals),
        'div3_avg': statistics.mean(div3_vals),
        
        # Count of non-zero dividers (clock throttling events)
        'throttle_count': sum(1 for e in entries if any([e['core0_div'], e['core1_div'], e['core2_div'], e['core3_div']])),
        
        # FIFO stress (count of entries where any FIFO >= 5)
        'fifo_stress_count': sum(1 for e in entries if max(e['fifo1_load'], e['fifo2_load'], e['fifo3_load']) >= 5),
    }
    
    stats['throttle_pct'] = 100 * stats['throttle_count'] / n
    stats['stress_pct'] = 100 * stats['fifo_stress_count'] / n
    
    return stats


def print_stats(stats):
    """Print formatted statistics."""
    if not stats:
        print("  No data")
        return
    
    print(f"  Entries: {stats['count']}")
    print(f"  RL Active: {stats['rl_enabled_pct']:.1f}%")
    print()
    print(f"  FIFO Load Averages (0-7, lower=better):")
    print(f"    FIFO1: {stats['fifo1_avg']:.2f} (max: {stats['fifo1_max']})")
    print(f"    FIFO2: {stats['fifo2_avg']:.2f} (max: {stats['fifo2_max']})")
    print(f"    FIFO3: {stats['fifo3_avg']:.2f} (max: {stats['fifo3_max']})")
    print()
    print(f"  Divider Averages (0=full speed):")
    print(f"    Core0 (resizer):   {stats['div0_avg']:.2f}")
    print(f"    Core1 (grayscale): {stats['div1_avg']:.2f}")
    print(f"    Core2 (diffamp):   {stats['div2_avg']:.2f}")
    print(f"    Core3 (blur):      {stats['div3_avg']:.2f}")
    print()
    print(f"  Throttle events: {stats['throttle_count']} ({stats['throttle_pct']:.1f}%)")
    print(f"  FIFO stress events (>=5): {stats['fifo_stress_count']} ({stats['stress_pct']:.1f}%)")


def compare_stats(stats_on, stats_off):
    """Compare RL-on vs RL-off statistics."""
    if not stats_on or not stats_off:
        print("Cannot compare - missing data")
        return
    
    print("\n" + "="*70)
    print("  COMPARISON: RL-ON vs RL-OFF")
    print("="*70)
    
    def delta_str(on_val, off_val, invert=False):
        """Format delta with arrow indicating improvement."""
        diff = on_val - off_val
        if invert:
            diff = -diff
        if abs(diff) < 0.01:
            return "≈"
        arrow = "↓" if diff < 0 else "↑"
        return f"{arrow}{abs(on_val - off_val):.2f}"
    
    print(f"\n  {'Metric':<30} {'RL-OFF':>10} {'RL-ON':>10} {'Change':>10}")
    print(f"  {'-'*30} {'-'*10} {'-'*10} {'-'*10}")
    
    # FIFO loads (lower is better, so negative change is good)
    print(f"  {'FIFO1 avg load':<30} {stats_off['fifo1_avg']:>10.2f} {stats_on['fifo1_avg']:>10.2f} {delta_str(stats_on['fifo1_avg'], stats_off['fifo1_avg'], True):>10}")
    print(f"  {'FIFO2 avg load':<30} {stats_off['fifo2_avg']:>10.2f} {stats_on['fifo2_avg']:>10.2f} {delta_str(stats_on['fifo2_avg'], stats_off['fifo2_avg'], True):>10}")
    print(f"  {'FIFO3 avg load':<30} {stats_off['fifo3_avg']:>10.2f} {stats_on['fifo3_avg']:>10.2f} {delta_str(stats_on['fifo3_avg'], stats_off['fifo3_avg'], True):>10}")
    
    # Max FIFO loads
    print(f"  {'FIFO1 max':<30} {stats_off['fifo1_max']:>10} {stats_on['fifo1_max']:>10}")
    print(f"  {'FIFO2 max':<30} {stats_off['fifo2_max']:>10} {stats_on['fifo2_max']:>10}")
    print(f"  {'FIFO3 max':<30} {stats_off['fifo3_max']:>10} {stats_on['fifo3_max']:>10}")
    
    # Dividers
    print(f"  {'Divider0 avg (resizer)':<30} {stats_off['div0_avg']:>10.2f} {stats_on['div0_avg']:>10.2f}")
    print(f"  {'Divider1 avg (gray)':<30} {stats_off['div1_avg']:>10.2f} {stats_on['div1_avg']:>10.2f}")
    print(f"  {'Divider2 avg (diffamp)':<30} {stats_off['div2_avg']:>10.2f} {stats_on['div2_avg']:>10.2f}")
    print(f"  {'Divider3 avg (blur)':<30} {stats_off['div3_avg']:>10.2f} {stats_on['div3_avg']:>10.2f}")
    
    # Throttle and stress
    print(f"  {'Throttle events %':<30} {stats_off['throttle_pct']:>10.1f} {stats_on['throttle_pct']:>10.1f}")
    print(f"  {'FIFO stress events %':<30} {stats_off['stress_pct']:>10.1f} {stats_on['stress_pct']:>10.1f}")
    
    print("="*70)
    
    # Summary verdict
    print("\n  VERDICT:")
    fifo_improvement = ((stats_off['fifo1_avg'] + stats_off['fifo2_avg'] + stats_off['fifo3_avg']) - 
                        (stats_on['fifo1_avg'] + stats_on['fifo2_avg'] + stats_on['fifo3_avg'])) / 3
    
    if fifo_improvement > 0.1:
        print(f"    ✓ RL agent IMPROVED FIFO balance by {fifo_improvement:.2f} on average")
    elif fifo_improvement < -0.1:
        print(f"    ✗ RL agent WORSENED FIFO balance by {-fifo_improvement:.2f} on average")
    else:
        print(f"    ≈ RL agent had MINIMAL effect on FIFO balance")
    
    if stats_on['throttle_pct'] > stats_off['throttle_pct'] + 5:
        print(f"    → RL agent actively throttled cores ({stats_on['throttle_pct']:.1f}% vs {stats_off['throttle_pct']:.1f}%)")
    
    print()


def find_log_files(directory):
    """Find all performance log CSV files in directory."""
    dir_path = Path(directory)
    files = list(dir_path.glob("*_perflog_*.csv"))
    return sorted(files)


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python analyze_rl_logs.py <rl_on.csv> <rl_off.csv>")
        print("  python analyze_rl_logs.py <output_directory>")
        return 1
    
    if len(sys.argv) == 2:
        # Single argument - assume it's a directory
        directory = sys.argv[1]
        if os.path.isdir(directory):
            files = find_log_files(directory)
            if not files:
                print(f"No *_perflog_*.csv files found in {directory}")
                return 1
            
            print(f"Found {len(files)} log files in {directory}")
            
            # Analyze each file
            all_stats = []
            for f in files:
                print(f"\n{'='*70}")
                print(f"  {f.name}")
                print("="*70)
                entries = load_log_csv(f)
                stats = analyze_logs(entries, f.name)
                print_stats(stats)
                all_stats.append(stats)
            
            # Try to separate into RL-on and RL-off based on rl_enabled_pct
            rl_on = [s for s in all_stats if s and s['rl_enabled_pct'] > 50]
            rl_off = [s for s in all_stats if s and s['rl_enabled_pct'] <= 50]
            
            if rl_on and rl_off:
                # Average the stats for comparison
                def avg_stats(stats_list):
                    result = {}
                    keys = ['fifo1_avg', 'fifo2_avg', 'fifo3_avg', 
                           'fifo1_max', 'fifo2_max', 'fifo3_max',
                           'div0_avg', 'div1_avg', 'div2_avg', 'div3_avg',
                           'throttle_pct', 'stress_pct', 'rl_enabled_pct']
                    for k in keys:
                        result[k] = statistics.mean([s[k] for s in stats_list])
                    result['count'] = sum(s['count'] for s in stats_list)
                    return result
                
                avg_on = avg_stats(rl_on)
                avg_off = avg_stats(rl_off)
                compare_stats(avg_on, avg_off)
            else:
                print("\nCannot compare - need both RL-on and RL-off log files")
        else:
            # Single CSV file
            entries = load_log_csv(sys.argv[1])
            stats = analyze_logs(entries, sys.argv[1])
            print(f"\n{'='*70}")
            print(f"  Analysis: {sys.argv[1]}")
            print("="*70)
            print_stats(stats)
    
    else:
        # Two files - compare
        rl_on_file = sys.argv[1]
        rl_off_file = sys.argv[2]
        
        print(f"\n{'='*70}")
        print(f"  RL-ON: {rl_on_file}")
        print("="*70)
        entries_on = load_log_csv(rl_on_file)
        stats_on = analyze_logs(entries_on, "RL-ON")
        print_stats(stats_on)
        
        print(f"\n{'='*70}")
        print(f"  RL-OFF: {rl_off_file}")
        print("="*70)
        entries_off = load_log_csv(rl_off_file)
        stats_off = analyze_logs(entries_off, "RL-OFF")
        print_stats(stats_off)
        
        compare_stats(stats_on, stats_off)
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
