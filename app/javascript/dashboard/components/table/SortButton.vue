<script setup>
defineProps({
  header: {
    type: Object,
    required: true,
  },
});

const sortIconMap = {
  default: 'i-lucide-chevrons-up-down',
  asc: 'i-lucide-chevron-up',
  desc: 'i-lucide-chevron-down',
};
</script>

<template>
  <!-- Sized and kept from shrinking: the icon is measured in em inside a flex
       header, so a title that wraps to two lines squeezed it smaller than the
       one next to it. -->
  <span
    class="shrink-0 size-3.5"
    :class="sortIconMap[header.column.getIsSorted() || 'default']"
  />
</template>
