export const isGroupExpanded = (expandedGroups, { namePlural }) =>
  expandedGroups.includes(namePlural);

export const toggleExpandedGroup = (expandedGroups, { namePlural }) =>
  isGroupExpanded(expandedGroups, { namePlural })
    ? expandedGroups.filter((group) => group !== namePlural)
    : [...expandedGroups, namePlural];

export const withExpandedChildren = (items, expandedGroups) =>
  items.flatMap((item) => {
    if (!item.children || !isGroupExpanded(expandedGroups, item)) {
      return [item];
    }

    return [item, ...item.children.map((child) => ({ ...child, isChild: true }))];
  });
