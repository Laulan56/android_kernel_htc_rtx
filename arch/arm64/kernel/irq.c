/*
 * Based on arch/arm/kernel/irq.c
 *
 * Copyright (C) 1992 Linus Torvalds
 * Modifications for ARM processor Copyright (C) 1995-2000 Russell King.
 * Support for Dynamic Tick Timer Copyright (C) 2004-2005 Nokia Corporation.
 * Dynamic Tick Timer written by Tony Lindgren <tony@atomide.com> and
 * Tuukka Tikkanen <tuukka.tikkanen@elektrobit.com>.
 * Copyright (C) 2012 ARM Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <linux/kernel_stat.h>
#include <linux/irq.h>
#include <linux/memory.h>
#include <linux/smp.h>
#include <linux/init.h>
#include <linux/irqchip.h>
#include <linux/seq_file.h>
#include <linux/vmalloc.h>
#ifdef CONFIG_HTC_POWER_DEBUG
#include <linux/types.h>
#include <linux/slab.h>
#include <soc/qcom/htc_util.h>
#endif

unsigned long irq_err_count;

DEFINE_PER_CPU(unsigned long *, irq_stack_ptr);

int arch_show_interrupts(struct seq_file *p, int prec)
{
	show_ipi_list(p, prec);
	seq_printf(p, "%*s: %10lu\n", prec, "Err", irq_err_count);
	return 0;
}

#ifdef CONFIG_HTC_POWER_DEBUG
#define IRQ_OUTPUT_BUFFER 1024
#define IRQ_PIECE_BUFFER 64
static unsigned int *previous_irqs = NULL;
static int pre_nr_irqs = 0;
static char irq_output[IRQ_OUTPUT_BUFFER];
static int debug = 0;
static void htc_show_interrupt(int i, int curr_nr_irqs) {
    struct irqaction *action;
    unsigned long flags;
    struct irq_desc *desc;
    char irq_piece[IRQ_PIECE_BUFFER];
    char name_resize[9];
    bool err = false;

    if (i < curr_nr_irqs) {
        desc = irq_to_desc(i);
        if (!desc) {
            if (debug)
                printk("[K] irq: get desc failed, continue\n");
            return;
        }
        raw_spin_lock_irqsave(&desc->lock, flags);
        action = desc->action;
        if (!action)
            goto unlock;
        if (!(kstat_irqs_cpu(i, 0)) || previous_irqs[i] == (kstat_irqs_cpu(i, 0)))
            goto unlock;

        memset(irq_piece, 0, sizeof(irq_piece));
        memset(name_resize, 0, sizeof(name_resize));

        if(action->name) {
            strncat(name_resize, action->name, 8);
        } else {
            if (debug)
                printk("[K] irq: [debug] irqaction name is null\n");
            strncat(name_resize, "(null)", 8);
        }
        err = kstat_irqs_cpu(i, 0) < previous_irqs[i];
        snprintf(irq_piece, sizeof(irq_piece), "%s(%d:%s,%u%s)",
                 strlen(irq_output) > 0 ? "," : "",
                 i,
                 name_resize,
                 err ? 0 : kstat_irqs_cpu(i, 0) - previous_irqs[i],
                 err ? "(prev > cur)" : "");

        if(strlen(irq_output) + strlen(irq_piece) <= IRQ_OUTPUT_BUFFER)
            safe_strcat(irq_output, irq_piece);
        else
            printk("[K] irq: [debug] IRQ_OUTPUT_BUFFER isn't enough\n");

        if (debug)
            k_pr_embedded("[K] irq: [debug] i=%d kstat_irqs_cpu=%u previous_irqs=%u\n",
                i, kstat_irqs_cpu(i, 0), previous_irqs[i]);

        previous_irqs[i] = kstat_irqs_cpu(i, 0);
unlock:
        raw_spin_unlock_irqrestore(&desc->lock, flags);
    } else if (i == curr_nr_irqs) {
        if (previous_irqs[i] == irq_err_count)
            return;
        printk("[K] irq: [Err] irq_err_count %lu\n", irq_err_count - previous_irqs[i]);
        previous_irqs[i] = irq_err_count;
    }
}

void htc_show_interrupts(void) {
    int i = 0, curr_nr_irqs = nr_irqs; // nr_irqs is a dynamic value

    if(pre_nr_irqs != curr_nr_irqs) {
        if (pre_nr_irqs != 0)
            if (debug)
                k_pr_embedded("[K] irq: [debug] alloc again\n");

        pre_nr_irqs = curr_nr_irqs;
        if(previous_irqs)
            kfree(previous_irqs);
        previous_irqs = kcalloc(curr_nr_irqs + 1, sizeof(unsigned int), GFP_KERNEL);

        if(!previous_irqs)
            goto malloc_failed;
    }

    memset(irq_output, 0, sizeof(irq_output));

    if (debug)
        k_pr_embedded("[K] irq: [debug] curr_nr_irqs=%d pre_nr_irqs=%d\n", curr_nr_irqs, pre_nr_irqs);

    for(i = 0; i <= curr_nr_irqs; i++)
        htc_show_interrupt(i, curr_nr_irqs);

    k_pr_embedded("[K] irq: %s\n", irq_output);
    return;

  malloc_failed:
    pre_nr_irqs = -1;
    pr_err("[K] irq: kcalloc failed\n");
}
#endif

void (*handle_arch_irq)(struct pt_regs *) = NULL;

void __init set_handle_irq(void (*handle_irq)(struct pt_regs *))
{
	if (handle_arch_irq)
		return;

	handle_arch_irq = handle_irq;
}

#ifdef CONFIG_VMAP_STACK
static void init_irq_stacks(void)
{
	int cpu;
	unsigned long *p;

	for_each_possible_cpu(cpu) {
		/*
		* To ensure that VMAP'd stack overflow detection works
		* correctly, the IRQ stacks need to have the same
		* alignment as other stacks.
		*/
		p = __vmalloc_node_range(IRQ_STACK_SIZE, THREAD_ALIGN,
					 VMALLOC_START, VMALLOC_END,
					 THREADINFO_GFP, PAGE_KERNEL,
					 0, cpu_to_node(cpu),
					 __builtin_return_address(0));

		per_cpu(irq_stack_ptr, cpu) = p;
	}
}
#else
/* irq stack only needs to be 16 byte aligned - not IRQ_STACK_SIZE aligned. */
DEFINE_PER_CPU_ALIGNED(unsigned long [IRQ_STACK_SIZE/sizeof(long)], irq_stack);

static void init_irq_stacks(void)
{
	int cpu;

	for_each_possible_cpu(cpu)
		per_cpu(irq_stack_ptr, cpu) = per_cpu(irq_stack, cpu);
}
#endif

void __init init_IRQ(void)
{
	init_irq_stacks();
	irqchip_init();
	if (!handle_arch_irq)
		panic("No interrupt controller found.");
}
